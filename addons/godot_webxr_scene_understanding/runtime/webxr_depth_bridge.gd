extends Node3D
## Harvests WebXR depth-sensing data (CPU path) into a live depth mesh.
##
## Depth sensing is the LIVE sensor view: per-frame range data covering
## whatever the headset currently looks at, including moving objects. It
## complements mesh detection (webxr_mesh_bridge.gd), which serves the
## platform's persistent reconstructed room geometry. Out of the box today
## Quest ships mesh detection while Android XR ships depth sensing, so a
## demo needs both, separately toggleable.
##
## Mechanism: a JS hook wraps the session's requestAnimationFrame. On a
## throttled tick it reads the primary view's XRCPUDepthInformation, samples
## it on a fixed grid via getDepthInMeters() (which applies the buffer
## transform and rawValueToMeters for us), unprojects each sample to the
## session reference space, and publishes the point grid. This node polls
## the grid and triangulates it into an ArrayMesh, culling triangles across
## depth discontinuities and coloring vertices by distance.
##
## Two layers render: the LIVE SWEEP (the current sensor view, refreshed
## ~4 Hz, distance-colored - the "scanner beam") and, with `accumulate` on,
## the persistent SCAN - triangulated surface patches accumulate wherever
## the sweep touches unscanned space (tracked in a world-anchored 5 cm
## voxel store), rendered in the same blue as the room-mesh visualization.
## Looking around progressively reconstructs the room from raw depth. This
## is the room-scan experience on devices that ship depth sensing but lock
## mesh detection behind browser flags (Android XR out of the box).
##
## The unprojection is exact for WebXR's (possibly asymmetric) perspective
## projections without a matrix inverse: with column-major projection P and
## eye depth d (meters), ndc.x = (P[0]*x + P[8]*z)/-z with z = -d, so
## x = d*(ndc.x + P[8])/P[0] and y = d*(ndc.y + P[9])/P[5].
##
## Requires the session to be granted "depth-sensing". cpu-optimized grants
## (Android XR) read XRCPUDepthInformation directly; gpu-optimized grants on
## WebGL sessions (Quest) decode the XRWebGLBinding depth texture with a
## grid-sized shader pass and read it back. get_status() reports honestly
## which precondition is missing.

const MESH_MATERIAL := preload("res://addons/godot_webxr_scene_understanding/runtime/depth_mesh_material.tres")

## Longest triangle edge kept, in meters; longer edges span depth
## discontinuities (object silhouettes) and would web the scene together.
@export var max_edge_length := 0.35
## Distance (from the headset at harvest time) mapped to the far color.
@export var far_distance := 6.0
## Keep every newly scanned surface patch, so looking around progressively
## builds a persistent triangulated room scan in the same style as the
## room-mesh visualization. This is what makes the demo a room scan on
## devices that ship depth sensing but lock mesh detection behind flags.
@export var accumulate := true
## Also draw the raw per-harvest sweep (the current sensor view, refreshed
## ~4 Hz, distance-colored). Off by default: a camera-locked mesh repainting
## in front of the user reads as visual noise next to the room-mesh-style
## scan - useful only when debugging the sensor itself.
@export var show_live_sweep := false
## The accumulated scan's tint - matches the room-mesh blue.
@export var scan_color := Color(0.08, 0.72, 1.0, 0.5)

## The scan is stored as half-meter world chunks, each holding the newest
## connected triangulated geometry that covered it - chunks REPLACE rather
## than accumulate, which is what keeps the mesh a single coherent layer
## (no stacking) with grid connectivity (no gaps), matching the platform
## reconstructions' behavior.
const SCAN_CHUNK_SIZE := 0.5
const SCAN_CHUNK_CAP := 4000

var auto_visualize := false

var _webxr: XRInterface
var _installed := false
var _poll_accum := 0.0
var _last_seq := 0
var _material: StandardMaterial3D
var _mesh_instance: MeshInstance3D
var _scan_instance: MeshInstance3D
# Vector3i chunk key -> { verts: Array[Vector3], indices: Array[int] }
# (plain Arrays: reference semantics during building; packed at rebuild).
var _scan_chunks := {}
var _scan_dirty := false
var _scan_rebuild_cooldown := 0.0
# The mesh bridge this toggle is currently driving (Android XR routing).
var _routed_bridge = null

func _ready() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		set_process(false)
		return
	_webxr = XRServer.find_interface("WebXR")
	if _webxr:
		_webxr.session_started.connect(_on_session_started)
		_webxr.session_ended.connect(_on_session_ended)
	add_to_group("webxr_depth_bridge")
	add_to_group("webxr_feature_provider")
	_material = MESH_MATERIAL.duplicate() as StandardMaterial3D
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "DepthMesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.visible = false
	add_child(_mesh_instance)
	_scan_instance = MeshInstance3D.new()
	_scan_instance.name = "DepthScan"
	_scan_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scan_instance.visible = false
	add_child(_scan_instance)
	_install_js_hook()

func _install_js_hook() -> void:
	if _installed:
		return
	_installed = true
	var js := Engine.get_singleton("JavaScriptBridge")
	js.eval("""
(function () {
	if (window.GodotWebXRDepthBridge) { return; }
	const bridge = {
		harvest: false, refType: 'local-floor', _ref: null, _refPending: false,
		seq: 0, frame: null, intervalMs: 250, _last: 0,
		gridW: 48, gridH: 36, status: 'idle', usage: '', format: '', size: '', path: '',
		// Accumulated scan: world-anchored voxel occupancy. Grid points whose
		// cell is NEW this harvest get flagged fresh, so the consumer can
		// accumulate triangulated patches of only-new surface - looking
		// around builds a persistent room scan out of live depth.
		cellSize: 0.05, maxCells: 100000, cells: null, cellCount: 0,
	};
	window.GodotWebXRDepthBridge = bridge;

	// CPU path (Android XR): sample XRCPUDepthInformation on the grid.
	function cpuHarvestMeters(frame, view) {
		if (typeof frame.getDepthInformation !== 'function') {
			bridge.status = 'no-cpu-api';
			return null;
		}
		let d = null;
		try { d = frame.getDepthInformation(view); } catch (e) {
			bridge.status = 'error:' + e.name;
			return null;
		}
		if (!d) { bridge.status = 'no-data'; return null; }
		if (typeof d.getDepthInMeters !== 'function') { bridge.status = 'no-meters-api'; return null; }
		const gw = bridge.gridW, gh = bridge.gridH;
		const meters = new Float32Array(gw * gh);
		for (let gy = 0; gy < gh; gy++) {
			const v = gy / (gh - 1);
			for (let gx = 0; gx < gw; gx++) {
				let dm = 0;
				try { dm = d.getDepthInMeters(gx / (gw - 1), v); } catch (e) { dm = 0; }
				meters[gy * gw + gx] = dm;
			}
		}
		bridge.path = 'cpu';
		bridge.status = 'ok';
		bridge.size = d.width + 'x' + d.height;
		return meters;
	}

	// GPU path (Quest: gpu-optimized-only grants on WebGL sessions): decode
	// the XRWebGLBinding depth texture into a grid-sized RGBA8 target with a
	// tiny shader pass and read it back. Runs on the engine's own WebGL2
	// context inside the rAF (XR textures are frame-scoped), with full GL
	// state save/restore around the pass.
	function gpuHarvestMeters(frame, view) {
		const g = bridge._gpu || (bridge._gpu = {});
		if (g.fail) { bridge.status = g.failWhy; return null; }
		const gw = bridge.gridW, gh = bridge.gridH;
		if (!g.gl) {
			const c = (typeof GodotConfig !== 'undefined' && GodotConfig.canvas) ? GodotConfig.canvas : document.querySelector('canvas');
			g.gl = c ? c.getContext('webgl2') : null;
			if (!g.gl) {
				g.fail = true; g.failWhy = 'gpu-no-webgl-context';
				bridge.status = g.failWhy;
				return null;
			}
		}
		const gl = g.gl;
		if (g.session !== frame.session) {
			try {
				g.binding = new XRWebGLBinding(frame.session, gl);
				g.session = frame.session;
			} catch (e) { bridge.status = 'gpu-binding-fail:' + e.name; return null; }
		}
		if (typeof g.binding.getDepthInformation !== 'function') {
			g.fail = true; g.failWhy = 'gpu-api-missing';
			bridge.status = g.failWhy;
			return null;
		}
		let d = null;
		try { d = g.binding.getDepthInformation(view); } catch (e) {
			bridge.status = 'gpu-error:' + e.name;
			return null;
		}
		if (!d || !d.texture) { bridge.status = 'no-data'; return null; }
		// The delivered texture's exact shape varies per browser (2D vs
		// array, 8-bit pair vs 16-bit normalized vs float). Self-calibrate:
		// cycle decode/sampler combos until a readback yields valid depths,
		// then lock. bridge.dbg carries the evidence either way.
		if (g.attempt === undefined) { g.attempt = 0; }
		const typeKnown = typeof d.textureType === 'string' && d.textureType.length > 0;
		let isArray, mode;
		// If the browser exposes the depth camera's own projection matrix,
		// the exact conversion derives from it: raw = -P10 + P14/m, so
		// m = P14/(raw + P10) - no guessed planes (mode 5, sign-agnostic).
		const pm = (d.projectionMatrix && d.projectionMatrix.length >= 16) ? d.projectionMatrix : null;
		if (g.locked) {
			isArray = g.locked.arr; mode = g.locked.mode;
		} else {
			mode = g.attempt % 6;
			isArray = typeKnown ? (d.textureType === 'texture-array') : (Math.floor(g.attempt / 6) % 2 === 1);
			if (g.attempt === 0 && bridge.format === 'float32') { mode = 1; }
			if (mode === 5 && !pm) {
				g.attempt++;
				bridge.status = 'calibrating';
				return null;
			}
		}
		// The depth map may carry its own projection range - but only trust
		// it when it is actually usable (Quest exposes the fields holding
		// zero, which turns the linearization into NaN); otherwise the
		// session's planes.
		const rs = frame.session.renderState;
		let depthNear = (rs && isFinite(rs.depthNear) && rs.depthNear > 0.0001) ? rs.depthNear : 0.1;
		let depthFar = (rs && isFinite(rs.depthFar) && rs.depthFar > depthNear) ? rs.depthFar : 1000.0;
		if (isFinite(d.depthNear) && d.depthNear > 0.0001 && isFinite(d.depthFar) && d.depthFar > d.depthNear) {
			depthNear = d.depthNear;
			depthFar = d.depthFar;
		}
		try {
			if (!g.fbo) {
				g.tex = gl.createTexture();
				gl.activeTexture(gl.TEXTURE0);
				const prevTex = gl.getParameter(gl.TEXTURE_BINDING_2D);
				gl.bindTexture(gl.TEXTURE_2D, g.tex);
				gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gw, gh, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
				gl.bindTexture(gl.TEXTURE_2D, prevTex);
				g.fbo = gl.createFramebuffer();
				const prevFbo = gl.getParameter(gl.DRAW_FRAMEBUFFER_BINDING);
				gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, g.fbo);
				gl.framebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, g.tex, 0);
				gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, prevFbo);
				g.vao = gl.createVertexArray();
				g.buf = new Uint8Array(gw * gh * 4);
			}
			const progKey = isArray ? 'progArr' : 'prog2d';
			if (!g[progKey]) {
				const vs = '#version 300 es\\nvoid main(){vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));gl_Position=vec4(p*2.0-1.0,0.0,1.0);}';
				const samp = isArray ? 'uniform highp sampler2DArray depthTex;' : 'uniform highp sampler2D depthTex;';
				const fetch = isArray ? 'texture(depthTex, vec3(uv, 0.0))' : 'texture(depthTex, uv)';
				const fs = '#version 300 es\\nprecision highp float;\\n' + samp +
					'\\nuniform mat4 uvTransform;\\nuniform vec2 gridSize;\\nuniform int fmt;\\nuniform float rawToMeters;\\nuniform vec2 nearFar;\\nuniform vec2 pmv;\\nout vec4 outColor;\\n' +
					'void main(){\\n' +
					'  vec2 nv = vec2(floor(gl_FragCoord.x) / (gridSize.x - 1.0), floor(gl_FragCoord.y) / (gridSize.y - 1.0));\\n' +
					'  vec2 uv = (uvTransform * vec4(nv, 0.0, 1.0)).xy;\\n' +
					'  vec4 t = ' + fetch + ';\\n' +
					// fmt 0: two 8-bit channels (luminance-alpha style);
					// fmt 1: float meters in r; fmt 2: 16-bit normalized in r;
					// fmt 3: forward nonlinear depth-buffer value in r;
					// fmt 4: reversed-z nonlinear depth-buffer value in r
					// (both linearized with the depth map's near/far planes).
					'  float m;\\n' +
					'  if (fmt == 3) {\\n' +
					'    m = nearFar.x * nearFar.y / max(nearFar.y - t.r * (nearFar.y - nearFar.x), 0.0001);\\n' +
					'  } else if (fmt == 4) {\\n' +
					'    m = nearFar.x * nearFar.y / max(nearFar.x + t.r * (nearFar.y - nearFar.x), 0.0001);\\n' +
					'  } else if (fmt == 5) {\\n' +
					'    m = abs(pmv.y / (t.r + pmv.x));\\n' +
					'  } else {\\n' +
					'    float raw = (fmt == 0) ? dot(t.ra, vec2(255.0, 255.0 * 256.0)) : ((fmt == 1) ? t.r : t.r * 65535.0);\\n' +
					'    m = raw * rawToMeters;\\n' +
					'  }\\n' +
					'  float nvd = clamp(m / 8.0, 0.0, 1.0);\\n' +
					'  float hi = floor(nvd * 255.0) / 255.0;\\n' +
					'  float lo = fract(nvd * 255.0);\\n' +
					'  outColor = vec4(hi, lo, 0.0, 1.0);\\n' +
					'}';
				const mk = function (type, src) {
					const sh = gl.createShader(type);
					gl.shaderSource(sh, src);
					gl.compileShader(sh);
					if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) { throw new Error(gl.getShaderInfoLog(sh)); }
					return sh;
				};
				const prog = gl.createProgram();
				gl.attachShader(prog, mk(gl.VERTEX_SHADER, vs));
				gl.attachShader(prog, mk(gl.FRAGMENT_SHADER, fs));
				gl.linkProgram(prog);
				if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) { throw new Error(gl.getProgramInfoLog(prog)); }
				g[progKey] = prog;
				g[progKey + '_u'] = {
					tex: gl.getUniformLocation(prog, 'depthTex'),
					xf: gl.getUniformLocation(prog, 'uvTransform'),
					grid: gl.getUniformLocation(prog, 'gridSize'),
					fmt: gl.getUniformLocation(prog, 'fmt'),
					r2m: gl.getUniformLocation(prog, 'rawToMeters'),
					nf: gl.getUniformLocation(prog, 'nearFar'),
					pmv: gl.getUniformLocation(prog, 'pmv'),
				};
			}
			// Save every piece of GL state the pass touches; the engine
			// assumes its cached state survives between its own frames.
			const s = {
				drawFbo: gl.getParameter(gl.DRAW_FRAMEBUFFER_BINDING),
				readFbo: gl.getParameter(gl.READ_FRAMEBUFFER_BINDING),
				prog: gl.getParameter(gl.CURRENT_PROGRAM),
				vao: gl.getParameter(gl.VERTEX_ARRAY_BINDING),
				activeTex: gl.getParameter(gl.ACTIVE_TEXTURE),
				viewport: gl.getParameter(gl.VIEWPORT),
				scissor: gl.isEnabled(gl.SCISSOR_TEST),
				blend: gl.isEnabled(gl.BLEND),
				depth: gl.isEnabled(gl.DEPTH_TEST),
				cull: gl.isEnabled(gl.CULL_FACE),
				stencil: gl.isEnabled(gl.STENCIL_TEST),
				rasterDiscard: gl.isEnabled(gl.RASTERIZER_DISCARD),
				colorMask: gl.getParameter(gl.COLOR_WRITEMASK),
				packBuf: gl.getParameter(gl.PIXEL_PACK_BUFFER_BINDING),
				packAlign: gl.getParameter(gl.PACK_ALIGNMENT),
			};
			gl.activeTexture(gl.TEXTURE0);
			s.tex2d = gl.getParameter(gl.TEXTURE_BINDING_2D);
			s.tex2da = gl.getParameter(gl.TEXTURE_BINDING_2D_ARRAY);
			try {
				gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, g.fbo);
				gl.viewport(0, 0, gw, gh);
				gl.disable(gl.SCISSOR_TEST);
				gl.disable(gl.BLEND);
				gl.disable(gl.DEPTH_TEST);
				gl.disable(gl.CULL_FACE);
				gl.disable(gl.STENCIL_TEST);
				gl.disable(gl.RASTERIZER_DISCARD);
				gl.colorMask(true, true, true, true);
				const prog = g[progKey];
				const u = g[progKey + '_u'];
				gl.useProgram(prog);
				gl.bindVertexArray(g.vao);
				if (isArray) { gl.bindTexture(gl.TEXTURE_2D_ARRAY, d.texture); } else { gl.bindTexture(gl.TEXTURE_2D, d.texture); }
				gl.uniform1i(u.tex, 0);
				gl.uniformMatrix4fv(u.xf, false, d.normDepthBufferFromNormView.matrix);
				gl.uniform2f(u.grid, gw, gh);
				gl.uniform1i(u.fmt, mode);
				gl.uniform1f(u.r2m, d.rawValueToMeters);
				gl.uniform2f(u.nf, depthNear, depthFar);
				gl.uniform2f(u.pmv, pm ? pm[10] : 0.0, pm ? pm[14] : 0.0);
				gl.drawArrays(gl.TRIANGLES, 0, 3);
				gl.bindFramebuffer(gl.READ_FRAMEBUFFER, g.fbo);
				gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
				gl.pixelStorei(gl.PACK_ALIGNMENT, 4);
				gl.readPixels(0, 0, gw, gh, gl.RGBA, gl.UNSIGNED_BYTE, g.buf);
			} finally {
				gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, s.drawFbo);
				gl.bindFramebuffer(gl.READ_FRAMEBUFFER, s.readFbo);
				gl.useProgram(s.prog);
				gl.bindVertexArray(s.vao);
				gl.activeTexture(gl.TEXTURE0);
				gl.bindTexture(gl.TEXTURE_2D, s.tex2d);
				gl.bindTexture(gl.TEXTURE_2D_ARRAY, s.tex2da);
				gl.activeTexture(s.activeTex);
				gl.viewport(s.viewport[0], s.viewport[1], s.viewport[2], s.viewport[3]);
				if (s.scissor) { gl.enable(gl.SCISSOR_TEST); }
				if (s.blend) { gl.enable(gl.BLEND); }
				if (s.depth) { gl.enable(gl.DEPTH_TEST); }
				if (s.cull) { gl.enable(gl.CULL_FACE); }
				if (s.stencil) { gl.enable(gl.STENCIL_TEST); }
				if (s.rasterDiscard) { gl.enable(gl.RASTERIZER_DISCARD); }
				gl.colorMask(s.colorMask[0], s.colorMask[1], s.colorMask[2], s.colorMask[3]);
				gl.bindBuffer(gl.PIXEL_PACK_BUFFER, s.packBuf);
				gl.pixelStorei(gl.PACK_ALIGNMENT, s.packAlign);
			}
			const meters = new Float32Array(gw * gh);
			const buf = g.buf;
			// Shader row r encodes view-coord v = r/(gh-1); readPixels also
			// returns row 0 first, so indices line up with the grid loop.
			let valid = 0;
			let vmn = 1e9, vmx = -1e9;
			for (let i = 0; i < gw * gh; i++) {
				const nvd = buf[i * 4] / 255.0 + buf[i * 4 + 1] / 65025.0;
				const m = nvd * 8.0;
				meters[i] = m;
				if (m > 0.1 && m < 8.0) {
					valid++;
					if (m < vmn) { vmn = m; }
					if (m > vmx) { vmx = m; }
				}
			}
			const spread = (valid > 0) ? (vmx - vmn) : 0;
			bridge.dbg = 'type=' + (d.textureType || '?') + ' fmt=' + (bridge.format || '?') + ' mode=' + mode + (isArray ? 'A' : '2') + ' r2m=' + Number(d.rawValueToMeters).toPrecision(3) + ' nf=' + depthNear.toFixed(2) + '/' + depthFar.toFixed(0) + ' rawNF=' + String(d.depthNear) + '/' + String(d.depthFar) + ' pm=' + (pm ? pm[10].toPrecision(3) + ',' + pm[14].toPrecision(3) : 'n') + ' range=' + (valid ? vmn.toFixed(2) + '..' + vmx.toFixed(2) : 'none') + ' valid=' + valid + ' spread=' + spread.toFixed(2) + ' try=' + g.attempt;
			// DEPTHDBG: strip after Quest decode is settled - the tap carries
			// every calibration attempt so nobody has to read status lines.
			console.log('DEPTHDBG ' + bridge.dbg + (g.locked ? ' LOCKED' : ''));
			if (!g.locked) {
				// Room-plausibility gates: coverage, variation, reach (a
				// normalized decode varies but never exceeds ~1m = a wall in
				// the user's face), AND temporal consistency - a wrong
				// linearization amplifies sensor noise into meters of jitter,
				// so its stats jump wildly between readings; demand two
				// agreeing readings of the same combo before trusting it.
				if (valid > (gw * gh) * 0.25 && spread > 0.25 && vmx > 1.5) {
					const skey = mode + (isArray ? 'A' : '2');
					if (!g.pendingStats) { g.pendingStats = {}; }
					const prev = g.pendingStats[skey];
					if (prev && Math.abs(prev.vmx - vmx) < 1.0 && Math.abs(prev.spread - spread) < 0.8) {
						g.locked = { arr: isArray, mode: mode };
						console.log('DEPTHDBG LOCKING mode=' + mode + (isArray ? 'A' : '2') + ' spread=' + spread.toFixed(2) + ' vmx=' + vmx.toFixed(2));
					} else {
						g.pendingStats[skey] = { vmx: vmx, spread: spread };
						g.attempt++;
						bridge.path = 'gpu';
						bridge.status = 'calibrating';
						return null;
					}
				} else if (g.attempt >= 24) {
					g.fail = true;
					g.failWhy = 'gpu-calibration-failed [' + bridge.dbg + ']';
					bridge.status = g.failWhy;
					return null;
				} else {
					g.attempt++;
					bridge.path = 'gpu';
					bridge.status = 'calibrating';
					return null;
				}
			}
			bridge.path = 'gpu';
			bridge.status = 'ok';
			bridge.size = d.width + 'x' + d.height;
			return meters;
		} catch (e) {
			g.fail = true; g.failWhy = 'gpu-pass-fail:' + (e && e.message ? String(e.message).slice(0, 80) : 'unknown');
			bridge.status = g.failWhy;
			return null;
		}
	}

	const orig = XRSession.prototype.requestAnimationFrame;
	XRSession.prototype.requestAnimationFrame = function (cb) {
		return orig.call(this, function (t, frame) {
			try {
				if (bridge.harvest) {
					const s = frame.session;
					bridge.usage = s.depthUsage || '';
					bridge.format = s.depthDataFormat || '';
					if (!bridge._ref && !bridge._refPending) {
						bridge._refPending = true;
						frame.session.requestReferenceSpace(bridge.refType)
							.then((r) => { bridge._ref = r; })
							.catch(() => { bridge._refPending = false; });
					}
					if (bridge._ref && (t - bridge._last) >= bridge.intervalMs) {
						// Throttle attempts too, not just successes; a
						// failing path must not retry at headset frame rate.
						bridge._last = t;
						const vp = frame.getViewerPose(bridge._ref);
						if (vp && vp.views.length) {
							const view = vp.views[0];
							// gpu-optimized grants refuse the CPU API by
							// spec; go straight to the readback path there.
							const meters = (bridge.usage === 'gpu-optimized')
								? gpuHarvestMeters(frame, view)
								: cpuHarvestMeters(frame, view);
							if (meters) {
								bridge._last = t;
								const p = view.projectionMatrix;
								const tr = view.transform.matrix;
								const gw = bridge.gridW, gh = bridge.gridH;
								const pts = new Array(gw * gh * 3);
								const val = new Array(gw * gh);
								const fresh = new Array(gw * gh);
								for (let gy = 0; gy < gh; gy++) {
									// Normalized view coords have a top-left
									// origin (y down); NDC y points up.
									const v = gy / (gh - 1);
									const ny = 1 - 2 * v;
									for (let gx = 0; gx < gw; gx++) {
										const u = gx / (gw - 1);
										const i = gy * gw + gx;
										const dm = meters[i];
										if (!(dm > 0.1 && dm < 8.0)) {
											val[i] = 0;
											fresh[i] = 0;
											pts[i * 3] = 0; pts[i * 3 + 1] = 0; pts[i * 3 + 2] = 0;
											continue;
										}
										const nx = 2 * u - 1;
										const ex = dm * (nx + p[8]) / p[0];
										const ey = dm * (ny + p[9]) / p[5];
										const ez = -dm;
										// View pose -> reference space (column-major).
										const wx = tr[0] * ex + tr[4] * ey + tr[8] * ez + tr[12];
										const wy = tr[1] * ex + tr[5] * ey + tr[9] * ez + tr[13];
										const wz = tr[2] * ex + tr[6] * ey + tr[10] * ez + tr[14];
										val[i] = 1;
										// mm precision keeps the poll payload small.
										pts[i * 3] = Math.round(wx * 1000) / 1000;
										pts[i * 3 + 1] = Math.round(wy * 1000) / 1000;
										pts[i * 3 + 2] = Math.round(wz * 1000) / 1000;
										fresh[i] = 0;
										if (!bridge.cells) { bridge.cells = new Set(); }
										if (bridge.cellCount < bridge.maxCells) {
											const cs = bridge.cellSize;
											const bx = Math.round(wx / cs);
											const by = Math.round(wy / cs);
											const bz = Math.round(wz / cs);
											const key = bx + ',' + by + ',' + bz;
											if (!bridge.cells.has(key)) {
												bridge.cellCount++;
												fresh[i] = 1;
												// Claim a one-cell shell too: sensor noise
												// re-lands repeat views of the same surface
												// in neighboring voxels, which would tile
												// the same wall on top of itself forever.
												for (let ox = -1; ox <= 1; ox++) {
													for (let oy = -1; oy <= 1; oy++) {
														for (let oz = -1; oz <= 1; oz++) {
															bridge.cells.add((bx + ox) + ',' + (by + oy) + ',' + (bz + oz));
														}
													}
												}
											}
										}
									}
								}
								bridge.frame = {
									seq: ++bridge.seq, gw: gw, gh: gh, pts: pts, val: val, fresh: fresh,
									eye: [tr[12], tr[13], tr[14]],
								};
							}
						}
					}
				}
			} catch (e) { /* never break the app's frame loop */ }
			cb(t, frame);
		});
	};
}())
""", true)

func set_visualize(p_on: bool) -> void:
	auto_visualize = p_on
	# David's product call: on Android XR the platform's own streaming
	# reconstruction (the room-mesh pipeline) IS the live depth-sensing
	# visualization - same sensor underneath, better fusion - so the toggle
	# drives the mesh bridge there whenever the platform serves mesh data.
	# Quest stays on the raw-depth scan (its room mesh is a static stored
	# space, a different concept), as do flag-less Android XR browsers
	# (mesh-detection withheld -> raw depth is all there is).
	if p_on:
		var routed = _platform_mesh_bridge()
		if routed != null:
			_routed_bridge = routed
			routed.set_visualize(true)
			return
	elif _routed_bridge != null:
		_routed_bridge.set_visualize(false)
		_routed_bridge = null
		return
	var js := Engine.get_singleton("JavaScriptBridge")
	js.eval("window.GodotWebXRDepthBridge && (window.GodotWebXRDepthBridge.harvest = %s);" % ("true" if p_on else "false"), true)
	_mesh_instance.visible = p_on and show_live_sweep
	_scan_instance.visible = p_on and accumulate
	if not p_on:
		# Live sensor data goes stale instantly; free it rather than freeze it.
		_mesh_instance.mesh = null
		_last_seq = 0
		_clear_scan()

## The mesh bridge to route through on platforms whose detectedMeshes are a
## live depth-driven stream (Android XR), or null to use the raw-depth scan.
func _platform_mesh_bridge():
	var bridges := get_tree().get_nodes_in_group("webxr_mesh_bridge")
	if bridges.is_empty():
		return null
	if not bridges[0].has_method("is_dynamic_mesh_platform") or not bridges[0].is_dynamic_mesh_platform():
		return null
	# Route only when the platform actually serves mesh data (on Android XR
	# today that needs the browser's Incubations/Mesh Detection flags).
	var prop := str(Engine.get_singleton("JavaScriptBridge").eval("window.GodotWebXRMeshBridge ? String(window.GodotWebXRMeshBridge.meshProp) : ''", true))
	if prop.begins_with("set:") or bridges[0].get_surface_count() > 0:
		return bridges[0]
	return null

func _clear_scan() -> void:
	_scan_chunks.clear()
	_scan_dirty = false
	_scan_instance.mesh = null
	Engine.get_singleton("JavaScriptBridge").eval("window.GodotWebXRDepthBridge && (window.GodotWebXRDepthBridge.frame = null, window.GodotWebXRDepthBridge.cells = new Set(), window.GodotWebXRDepthBridge.cellCount = 0);", true)

func get_status() -> String:
	if _routed_bridge != null:
		return "Depth sensing (platform reconstruction): %s" % _routed_bridge.get_status()
	if not _installed:
		return "Depth sensing: web only."
	if _webxr == null or not _webxr.is_initialized():
		return "Depth sensing: waiting for an immersive session."
	var features := str(_webxr.get("enabled_features"))
	if not features.contains("depth-sensing"):
		return "Depth sensing: not granted by the browser (on some devices it hides behind chrome://flags WebXR Incubations)."
	var js := Engine.get_singleton("JavaScriptBridge")
	var usage := str(js.eval("window.GodotWebXRDepthBridge ? window.GodotWebXRDepthBridge.usage : '';", true))
	var status := str(js.eval("window.GodotWebXRDepthBridge ? window.GodotWebXRDepthBridge.status : '';", true))
	var size := str(js.eval("window.GodotWebXRDepthBridge ? window.GodotWebXRDepthBridge.size : '';", true))
	if not auto_visualize:
		return "Depth sensing: granted (usage: %s). Toggle on to harvest." % (usage if not usage.is_empty() else "pending")
	var path := str(js.eval("window.GodotWebXRDepthBridge ? String(window.GodotWebXRDepthBridge.path || '') : '';", true))
	match status:
		"ok":
			var cells := int(str(js.eval("window.GodotWebXRDepthBridge ? window.GodotWebXRDepthBridge.cellCount : 0;", true)).to_float())
			var path_desc := "CPU depth" if path == "cpu" else "GPU depth readback"
			if cells == 0 and path == "gpu":
				var dbg := str(js.eval("window.GodotWebXRDepthBridge ? String(window.GodotWebXRDepthBridge.dbg || '') : '';", true))
				return "Depth sensing (GPU readback) calibrating... [%s]" % dbg
			return "Depth sensing LIVE (%s): %s sensor. Look around to scan - %d points captured." % [path_desc, size, cells]
		"calibrating":
			var cal_dbg := str(js.eval("window.GodotWebXRDepthBridge ? String(window.GodotWebXRDepthBridge.dbg || '') : '';", true))
			return "Depth sensing (GPU readback) calibrating... [%s]" % cal_dbg
		"no-data":
			return "Depth sensing: granted (usage: %s) but no depth data served yet." % usage
		"no-cpu-api", "no-meters-api":
			return "Depth sensing: granted, but this browser lacks the CPU depth API (%s)." % status
		"gpu-no-webgl-context":
			return "Depth sensing: granted GPU-only, and this WebGPU session's browser has not shipped XRGPUBinding depth - upcoming browser feature."
		"gpu-api-missing":
			return "Depth sensing: granted GPU-only, but this browser lacks XRWebGLBinding.getDepthInformation."
		"idle":
			return "Depth sensing: harvest starting..."
		_:
			return "Depth sensing: granted but unreadable (%s, usage: %s)." % [status, usage]

func _on_session_started() -> void:
	# Match the hook's reference space to the one Godot's session got, so
	# harvested points land in tracked-node space.
	var js := Engine.get_singleton("JavaScriptBridge")
	var ref_type := str(_webxr.get("reference_space_type"))
	if not ref_type.is_empty():
		js.eval("window.GodotWebXRDepthBridge && (window.GodotWebXRDepthBridge.refType = '%s', window.GodotWebXRDepthBridge._ref = null, window.GodotWebXRDepthBridge._refPending = false);" % ref_type, true)
	# Fresh material per session: some browsers lose bindings to pre-session
	# GPU resources (same lesson as the mesh bridge). All shader-codegen
	# flags (vertex color, transparency, cull) live in the baked .tres.
	_material = MESH_MATERIAL.duplicate() as StandardMaterial3D
	_mesh_instance.material_override = _material
	_scan_instance.material_override = _material

func _on_session_ended() -> void:
	# The routed mesh bridge handles its own session teardown; just drop the
	# reference so the next toggle re-evaluates the platform route.
	_routed_bridge = null
	_mesh_instance.mesh = null
	_last_seq = 0
	_clear_scan()

func _process(delta: float) -> void:
	if not auto_visualize:
		return
	if _scan_rebuild_cooldown > 0.0:
		_scan_rebuild_cooldown -= delta
	elif _scan_dirty:
		_rebuild_scan_mesh()
	_poll_accum += delta
	if _poll_accum < 0.25:
		return
	_poll_accum = 0.0
	var js := Engine.get_singleton("JavaScriptBridge")
	var payload := str(js.eval("(window.GodotWebXRDepthBridge && window.GodotWebXRDepthBridge.frame && window.GodotWebXRDepthBridge.frame.seq > %d) ? JSON.stringify(window.GodotWebXRDepthBridge.frame) : '';" % _last_seq, true))
	if payload.is_empty():
		return
	var data: Variant = JSON.parse_string(payload)
	if data == null:
		return
	_last_seq = int(data["seq"])
	_rebuild_mesh(data)

## Bucket this harvest's connected triangles into world chunks by centroid
## and REPLACE each covered chunk's geometry with the newest version.
func _update_scan_chunks(verts: PackedVector3Array, tris: PackedInt32Array) -> void:
	var touched := {}
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var centroid: Vector3 = (verts[a] + verts[b] + verts[c]) / 3.0
		var ck := Vector3i(floori(centroid.x / SCAN_CHUNK_SIZE), floori(centroid.y / SCAN_CHUNK_SIZE), floori(centroid.z / SCAN_CHUNK_SIZE))
		if not touched.has(ck):
			touched[ck] = { "verts": [], "indices": [], "remap": {} }
		var chunk: Dictionary = touched[ck]
		var remap: Dictionary = chunk["remap"]
		var cverts: Array = chunk["verts"]
		var cidx: Array = chunk["indices"]
		for idx in [a, b, c]:
			if not remap.has(idx):
				remap[idx] = cverts.size()
				cverts.append(verts[idx])
			cidx.append(remap[idx])
	for ck in touched:
		var newc: Dictionary = touched[ck]
		newc.erase("remap")
		if _scan_chunks.has(ck):
			# A harvest grazing a chunk's edge must not wipe a well-covered
			# chunk with a sliver; keep the old geometry until a comparable
			# view replaces it.
			var old_n: int = (_scan_chunks[ck]["indices"] as Array).size()
			if (newc["indices"] as Array).size() * 2 < old_n:
				continue
		elif _scan_chunks.size() >= SCAN_CHUNK_CAP:
			continue
		_scan_chunks[ck] = newc
	if not touched.is_empty():
		_scan_dirty = true

## Rebuild the persistent scan mesh from the chunk store. Throttled: chunk
## replacement is cheap per harvest, the merged rebuild is the heavy step.
func _rebuild_scan_mesh() -> void:
	_scan_dirty = false
	_scan_rebuild_cooldown = 1.0
	var all_verts := PackedVector3Array()
	var all_colors := PackedColorArray()
	var all_indices := PackedInt32Array()
	for ck in _scan_chunks:
		var chunk: Dictionary = _scan_chunks[ck]
		var base := all_verts.size()
		var cverts: Array = chunk["verts"]
		var cidx: Array = chunk["indices"]
		for v in cverts:
			all_verts.append(v)
			all_colors.append(scan_color)
		for i in cidx:
			all_indices.append(base + int(i))
	if all_indices.is_empty():
		_scan_instance.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = all_verts
	arrays[Mesh.ARRAY_COLOR] = all_colors
	arrays[Mesh.ARRAY_INDEX] = all_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	_scan_instance.mesh = mesh

func _rebuild_mesh(data: Dictionary) -> void:
	var gw := int(data["gw"])
	var gh := int(data["gh"])
	var pts: Array = data["pts"]
	var val: Array = data["val"]
	var tris := PackedInt32Array()
	var eye_arr: Array = data["eye"]
	var eye := Vector3(eye_arr[0], eye_arr[1], eye_arr[2])

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(gw * gh)
	colors.resize(gw * gh)
	for i in gw * gh:
		var p := Vector3(pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2])
		verts[i] = p
		var dist := clampf(eye.distance_to(p) / far_distance, 0.0, 1.0)
		# Near cyan -> far deep blue, dimming with distance.
		colors[i] = Color.from_hsv(0.5 + 0.16 * dist, 0.85, 1.0 - 0.5 * dist, 0.85)

	var max_edge_sq := max_edge_length * max_edge_length
	var indices := PackedInt32Array()
	for gy in gh - 1:
		for gx in gw - 1:
			var i00 := gy * gw + gx
			var i10 := i00 + 1
			var i01 := i00 + gw
			var i11 := i01 + 1
			if not (val[i00] and val[i10] and val[i01] and val[i11]):
				continue
			# The diagonal is shared; checking it once covers both triangles.
			if verts[i00].distance_squared_to(verts[i11]) > max_edge_sq:
				continue
			# Godot front faces wind clockwise; these are clockwise as seen
			# from the harvesting eye, which depth surfaces always face.
			if verts[i00].distance_squared_to(verts[i10]) <= max_edge_sq \
					and verts[i10].distance_squared_to(verts[i11]) <= max_edge_sq:
				indices.append_array(PackedInt32Array([i00, i10, i11]))
				tris.append_array(PackedInt32Array([i00, i10, i11]))
			if verts[i00].distance_squared_to(verts[i01]) <= max_edge_sq \
					and verts[i01].distance_squared_to(verts[i11]) <= max_edge_sq:
				indices.append_array(PackedInt32Array([i00, i11, i01]))
				tris.append_array(PackedInt32Array([i00, i11, i01]))

	if accumulate and not tris.is_empty():
		_update_scan_chunks(verts, tris)
	if not show_live_sweep or indices.is_empty():
		_mesh_instance.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	_mesh_instance.mesh = mesh


## webxr_feature_provider contract, collected by webxr_bootstrap.gd before
## the session request. Depth sensing is an AR capability on today's
## browsers; requesting it in VR buys nothing.
func get_webxr_required_features(_session_mode: String) -> PackedStringArray:
	return PackedStringArray()

func get_webxr_optional_features(session_mode: String) -> PackedStringArray:
	if session_mode == "immersive-ar":
		return PackedStringArray(["depth-sensing"])
	return PackedStringArray()
