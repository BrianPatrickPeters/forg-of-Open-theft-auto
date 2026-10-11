class_name CityPlan
extends RefCounted
## Modular procedural city planner for Free Harbor.
##
## The old generator walked a fixed 32 m lattice and classified every block by
## its distance from the origin, so every city had the same streets, the same
## district rings and the same landmarks. This planner replaces that with a real
## staged pipeline whose every stage reads one seeded RNG:
##
##   1. layout      - street lines (pitch, jitter, dropped streets, alleys)
##   2. roads       - road class per line (arterial / street / alley) -> width
##   3. blocks      - rectangles enclosed by consecutive lines
##   4. zoning      - seeded district seed points, nearest-seed assignment
##   5. parcels     - block subdivision into plot-sized parcels
##   6. buildings   - one explicit build order per parcel (kind + size + style)
##   7. sidewalks   - sidewalk band per road class, crossings at junctions
##   8. decoration  - lamps, trees, benches, bins, bus stops along the streets
##
## Everything downstream (world.gd) is a pure consumer: it walks `roads`,
## `blocks` and `parcels` and turns them into meshes and collision boxes. The
## plan itself never touches the scene tree, so it can be generated and
## compared headlessly.
##
## A "reserved" rectangle is never crossed by a dropped street, an alley or a
## building plot. The downtown landmark plaza and the four safehouse estates
## are reserved, which is what keeps the shop kiosks, the exchange, the realtor
## and the estates standing on the exact block centres the rest of the game
## reads from CityWorld.

const D_DOWNTOWN := 0
const D_COMMERCIAL := 1
const D_RESIDENTIAL := 2
const D_SUBURBAN := 3
const D_INDUSTRIAL := 4
const D_PARK := 5
const D_PLAZA := 6
const D_RESERVED := 7      # landmark plaza / safehouse estate footprint
const D_OPEN := 8          # canal corridor and other unbuildable ground

const K_TOWER := "tower"
const K_MIDRISE := "midrise"
const K_ROWHOUSE := "rowhouse"
const K_VILLA := "villa"
const K_HOUSE := "house"
const K_SHED := "shed"
const K_STACK := "stack"
const K_PARK := "park"
const K_PLAZA := "plaza"

## Profile table. Each profile is a genuinely different urban plan, not a
## re-skin: the numbers below drive street pitch, how much streets wander,
## which streets vanish, how wide the roads are, how blocks are subdivided and
## which building kinds are used.
const PROFILES := {
	"old_town": {
		"label": "Old Town",
		"pitch": 24.0, "jitter": 3.2, "drop": 0.13, "alley": 0.45,
		"street_w": 8.0, "arterial_w": 13.0, "arterial_chance": 0.10,
		"zone_seeds": 7, "green": 0.10, "park_kind": "plaza",
		"zone_mix": [D_RESIDENTIAL, D_RESIDENTIAL, D_RESIDENTIAL, D_COMMERCIAL, D_PLAZA],
		"height": 0.55,
	},
	"modern_eu": {
		"label": "Modern European",
		"pitch": 32.0, "jitter": 1.4, "drop": 0.07, "alley": 0.16,
		"street_w": 12.0, "arterial_w": 19.0, "arterial_chance": 0.22,
		"zone_seeds": 8, "green": 0.09, "park_kind": "park",
		"zone_mix": [D_DOWNTOWN, D_COMMERCIAL, D_COMMERCIAL, D_RESIDENTIAL, D_RESIDENTIAL, D_PARK],
		"height": 1.0,
	},
	"suburban": {
		"label": "Suburban",
		"pitch": 44.0, "jitter": 1.0, "drop": 0.12, "alley": 0.03,
		"street_w": 11.0, "arterial_w": 15.0, "arterial_chance": 0.12,
		"zone_seeds": 6, "green": 0.22, "park_kind": "park",
		"zone_mix": [D_SUBURBAN, D_SUBURBAN, D_SUBURBAN, D_RESIDENTIAL, D_PARK],
		"height": 0.5,
	},
	"industrial": {
		"label": "Industrial",
		"pitch": 60.0, "jitter": 0.8, "drop": 0.16, "alley": 0.02,
		"street_w": 15.0, "arterial_w": 22.0, "arterial_chance": 0.30,
		"zone_seeds": 5, "green": 0.07, "park_kind": "park",
		"zone_mix": [D_INDUSTRIAL, D_INDUSTRIAL, D_INDUSTRIAL, D_COMMERCIAL, D_OPEN],
		"height": 0.35,
	},
	"downtown": {
		"label": "Commercial Downtown",
		"pitch": 28.0, "jitter": 0.9, "drop": 0.05, "alley": 0.30,
		"street_w": 13.0, "arterial_w": 21.0, "arterial_chance": 0.26,
		"zone_seeds": 6, "green": 0.06, "park_kind": "plaza",
		"zone_mix": [D_DOWNTOWN, D_DOWNTOWN, D_COMMERCIAL, D_COMMERCIAL, D_PLAZA],
		"height": 1.35,
	},
}

const PROFILE_ORDER := ["old_town", "modern_eu", "suburban", "industrial", "downtown"]

# Site frame â€” the city occupies [-extent, extent] on both axes.
const EXTENT := 208.0

var profile_id := "modern_eu"
var profile: Dictionary = {}
var seed_value := 0
var rng := RandomNumberGenerator.new()

# Street line positions (metres, world space) and their road widths.
var x_lines: Array[float] = []       # north-south streets (vary along X)
var z_lines: Array[float] = []       # east-west streets (vary along Z)
var x_width: Dictionary = {}         # float x -> width
var z_width: Dictionary = {}
var x_class: Dictionary = {}         # float x -> "arterial" | "street" | "alley"
var z_class: Dictionary = {}

var blocks: Array = []               # {x, z, w, d, district, parcels}
var reserved: Array = []             # Rect2 footprints the plan must not cross
var lamps: Array = []                # Vector2
var crossings: Array = []            # {x, z, horizontal} pedestrian crossings
var trees: Array = []                # {x, z, kind}
var props: Array = []                # {kind, x, z, yaw}

var river_cx := -64.0
var river_corridor := 26.0


func configure(p_seed: int, p_profile: String) -> void:
	seed_value = p_seed
	profile_id = p_profile if PROFILES.has(p_profile) else "modern_eu"
	profile = PROFILES[profile_id]


## Reserved footprints: the downtown landmark plaza and every safehouse estate.
## These keep the exact block centres the rest of the game reads.
static func reserved_footprints(safehouse_centres: Array) -> Array:
	var out: Array = [Rect2(-48.0, -16.0, 96.0, 64.0)]   # landmark plaza (3x2 blocks)
	for p in safehouse_centres:
		var px: float = p.x
		var pz: float = p.y
		var x0: float = minf(px, px + (-32.0 if px > 0.0 else 32.0))
		var z0: float = minf(pz, pz + (-32.0 if pz > 0.0 else 32.0))
		out.append(Rect2(x0, z0, 32.0, 32.0))
	return out


## Build the whole plan. Deterministic for a given (seed, profile).
func generate(river_centre: float, corridor: float, safehouse_centres: Array) -> void:
	river_cx = river_centre
	river_corridor = corridor
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	blocks.clear()
	lamps.clear()
	crossings.clear()
	trees.clear()
	props.clear()
	reserved = reserved_footprints(safehouse_centres)

	_stage_layout()
	_stage_roads()
	_stage_blocks()
	_stage_zone()
	_stage_parcels()
	_stage_streetscape()


# ---------------------------------------------------------------- 1. layout

## Street lines: an even profile-pitch sweep, then the canonical 32 m lattice
## lines that the reserved footprints depend on are pinned back in. Non-pinned
## lines wander by +/- profile.jitter, some are dropped (long blocks), and some
## wide blocks gain a mid-block alley.
func _stage_layout() -> void:
	var pitch: float = profile.pitch
	var span: float = EXTENT * 2.0
	var segments: int = maxi(4, roundi(span / pitch))
	var step: float = span / float(segments)

	var xs: Array[float] = []
	for i in range(segments + 1):
		xs.append(-EXTENT + i * step)
	var zs: Array[float] = xs.duplicate()

	var pins := _pinned_coords()
	for v in pins.x:
		xs.append(v)
	for v in pins.z:
		zs.append(v)

	xs = _snap_to_pins(xs, pins.x)
	zs = _snap_to_pins(zs, pins.z)
	x_lines = _settle_lines(xs, pins.x)
	z_lines = _settle_lines(zs, pins.z)

	# Alley: split an oversized block, but never inside a reserved footprint.
	x_lines = _insert_alleys(x_lines, pins.x, false)
	z_lines = _insert_alleys(z_lines, pins.z, true)
	x_lines = _unique_sorted(x_lines)
	z_lines = _unique_sorted(z_lines)


## The canonical 32 m lattice coordinates that fall inside a reserved rectangle.
## These are never jittered, dropped, or crossed by an alley.
func _pinned_coords() -> Dictionary:
	var lx: Array[float] = []
	var lz: Array[float] = []
	var start := -EXTENT
	var count := int(round((EXTENT * 2.0) / 32.0))
	for i in range(count + 1):
		var c := start + i * 32.0
		for rr in reserved:
			if c >= rr.position.x - 0.01 and c <= rr.position.x + rr.size.x + 0.01:
				lx.append(c)
				break
		for rr in reserved:
			if c >= rr.position.y - 0.01 and c <= rr.position.y + rr.size.y + 0.01:
				lz.append(c)
				break
	return {"x": _unique_sorted(lx), "z": _unique_sorted(lz)}


## Pull a sweep line that landed next to a pinned coordinate exactly onto it, so
## reserved blocks keep their exact centres after deduplication.
func _snap_to_pins(lines: Array[float], pins: Array) -> Array[float]:
	var snapped: Array[float] = []
	for v in lines:
		var best: float = v
		for p in pins:
			if absf(v - p) < 1.5:
				best = float(p)
				break
		snapped.append(best)
	return _unique_sorted(snapped)


func _is_pinned(v: float, pins: Array) -> bool:
	for p in pins:
		if absf(v - p) < 0.25:
			return true
	return false


## Jitter and drop the unpinned lines. Dropping is skipped where it would
## create a block more than ~2.4x the profile pitch, so the street network
## stays walkable instead of degenerating into a few giant superblocks.
func _settle_lines(lines: Array[float], pins: Array) -> Array[float]:
	var jitter: float = profile.jitter
	var drop: float = profile.drop
	var out: Array[float] = []
	var last_dropped := false
	for i in range(lines.size()):
		var v: float = lines[i]
		if _is_pinned(v, pins):
			out.append(v)
			last_dropped = false
			continue
		if i > 0 and i < lines.size() - 1 and not last_dropped and rng.randf() < drop:
			last_dropped = true
			continue
		last_dropped = false
		out.append(v + rng.randf_range(-jitter, jitter))
	out.sort()
	return out


## Add a narrow alley through blocks that came out much wider than the profile
## pitch, giving the old-town and downtown profiles back the tight grain their
## pitch alone does not deliver.
func _insert_alleys(lines: Array[float], pins: Array, along_z: bool) -> Array[float]:
	var chance: float = profile.alley
	if chance <= 0.0:
		return lines
	var out: Array[float] = []
	var limit: float = profile.pitch * 1.55
	for i in range(lines.size() - 1):
		out.append(lines[i])
		var gap: float = lines[i + 1] - lines[i]
		if gap <= limit or gap > limit * 2.4:
			continue
		var mid: float = (lines[i] + lines[i + 1]) * 0.5
		if _in_reserved_strip(mid, along_z):
			continue
		if rng.randf() < chance:
			_alley_coords[snappedf(mid, 0.01)] = true
			out.append(mid)
	out.append(lines[lines.size() - 1])
	return out


## True when a new street at this coordinate would cut a reserved footprint.
func _in_reserved_strip(coord: float, along_z: bool) -> bool:
	for rr in reserved:
		var lo: float = rr.position.y if along_z else rr.position.x
		var hi: float = lo + (rr.size.y if along_z else rr.size.x)
		if coord > lo - 1.0 and coord < hi + 1.0:
			return true
	return false


# ----------------------------------------------------------------- 2. roads

## Promote some streets to arterials and tag the thin ones as alleys.
func _stage_roads() -> void:
	var street_w: float = profile.street_w
	var arterial_w: float = profile.arterial_w
	var chance: float = profile.arterial_chance
	var pins := _pinned_coords()
	for v in x_lines:
		if _is_pinned(v, pins.x) or _in_reserved_strip(v, false):
			x_class[v] = "street"
			x_width[v] = street_w
			continue
		_classify(v, chance, street_w, arterial_w, true)
	for v in z_lines:
		if _is_pinned(v, pins.z) or _in_reserved_strip(v, true):
			z_class[v] = "street"
			z_width[v] = street_w
			continue
		_classify(v, chance, street_w, arterial_w, false)


func _classify(v: float, chance: float, street_w: float, arterial_w: float, along_x: bool) -> void:
	var is_alley := _alley_coords.has(snappedf(v, 0.01))
	var w := street_w
	var cls := "street"
	if is_alley:
		w = maxf(5.0, street_w * 0.45)
		cls = "alley"
	elif rng.randf() < chance:
		w = arterial_w
		cls = "arterial"
	if along_x:
		x_class[v] = cls
		x_width[v] = w
	else:
		z_class[v] = cls
		z_width[v] = w


## Roads emitted for the world to render: one entry per street line, already
## split so no strip enters the open canal corridor.
func roads() -> Array:
	var out: Array = []
	for v in x_lines:
		var w: float = x_width.get(v, profile.street_w)
		out.append({"horizontal": false, "coord": v, "width": w, "class": x_class.get(v, "street")})
	for v in z_lines:
		var w: float = z_width.get(v, profile.street_w)
		out.append({"horizontal": true, "coord": v, "width": w, "class": z_class.get(v, "street")})
	return out


## Distance from a point to the nearest street centreline on either axis.
## Used for prop placement so nothing lands in the carriageway.
func dist_to_street(x: float, z: float) -> float:
	var dx := _nearest_line(x_lines, x)
	var dz := _nearest_line(z_lines, z)
	return minf(dx, dz)


func _nearest_line(lines: Array[float], v: float) -> float:
	var best := INF
	for l in lines:
		best = minf(best, absf(l - v))
	return best


# ---------------------------------------------------------------- 3. blocks

func _stage_blocks() -> void:
	for i in range(x_lines.size() - 1):
		var x0: float = x_lines[i]
		var x1: float = x_lines[i + 1]
		for j in range(z_lines.size() - 1):
			var z0: float = z_lines[j]
			var z1: float = z_lines[j + 1]
			var w := x1 - x0
			var d := z1 - z0
			if w < 8.0 or d < 8.0:
				continue
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			blocks.append({
				"x": cx, "z": cz, "w": w, "d": d,
				"x0": x0, "x1": x1, "z0": z0, "z1": z1,
				"district": D_OPEN, "parcels": [],
			})


# ---------------------------------------------------------------- 4. zoning

## Seeded district seed points, then nearest-seed assignment. Two different
## seeds pick different seed points, so the same profile produces a different
## district map â€” not just a different set of building colours.
func _stage_zone() -> void:
	var count: int = maxi(2, int(profile.zone_seeds))
	var mix: Array = profile.zone_mix
	var seeds: Array = []
	for i in count:
		seeds.append({
			"x": rng.randf_range(-EXTENT * 0.86, EXTENT * 0.86),
			"z": rng.randf_range(-EXTENT * 0.86, EXTENT * 0.86),
			"district": mix[rng.randi() % mix.size()],
		})
	# The plaza footprint must stay a landmark block, and it should sit in the
	# middle of the commercial core, so seed one district point right on it.
	seeds.append({"x": 0.0, "z": 16.0, "district": D_DOWNTOWN if profile_id != "suburban" else D_RESIDENTIAL})

	var green: float = profile.green
	var park_kind: String = profile.park_kind
	for b in blocks:
		# Reserved blocks win first, so the landmark plaza is never overwritten,
		# then the open canal corridor, then the seeded district zone.
		if _in_any_reserved(b.x, b.z):
			b.district = D_RESERVED
			continue
		if _in_corridor(b.x, b.z):
			b.district = D_OPEN
			continue
		var bd: int = _zone_of_point(b.x, b.z, seeds)
		# Seeded green space: parks and plazas replace whole blocks.
		if rng.randf() < green:
			bd = D_PLAZA if park_kind == "plaza" else D_PARK
		b.district = bd


func _zone_of_point(x: float, z: float, seeds: Array) -> int:
	var best := D_RESIDENTIAL
	var bd := INF
	for s in seeds:
		var dd: float = Vector2(s.x - x, s.z - z).length()
		if dd < bd:
			bd = dd
			best = int(s.district)
	return best


func _in_any_reserved(x: float, z: float) -> bool:
	for rr in reserved:
		if x > rr.position.x and x < rr.position.x + rr.size.x \
			and z > rr.position.y and z < rr.position.y + rr.size.y:
			return true
	return false


func _in_corridor(x: float, z: float) -> bool:
	if absf(z) > EXTENT + 12.0:
		return false
	return absf(x - river_cx) < river_corridor + 12.0


# ------------------------------------------------------------- 5. parcels

## Subdivide each block into plots. The plot pattern is a property of the
## district, so an industrial block gets two big yards while an old-town block
## gets a tight row of six narrow plots.
func _stage_parcels() -> void:
	var height_scale: float = profile.height
	for b in blocks:
		var kind: int = b.district
		match kind:
			D_OPEN:
				b.parcels = []
			D_RESERVED:
				b.parcels = []
			D_PLAZA:
				b.parcels = [_parcel(b, 0.0, 0.0, b.w - 1.5, b.d - 1.5, 0.0, K_PLAZA, 0.0)]
			D_PARK:
				b.parcels = [_parcel(b, 0.0, 0.0, b.w - 1.5, b.d - 1.5, 0.0, K_PARK, 0.0)]
			D_INDUSTRIAL:
				b.parcels = _industrial_parcels(b, height_scale)
			D_DOWNTOWN:
				b.parcels = _tower_parcels(b, height_scale, true)
			D_COMMERCIAL:
				b.parcels = _tower_parcels(b, height_scale, false)
			D_SUBURBAN:
				b.parcels = _suburban_parcels(b)
			_:
				b.parcels = _residential_parcels(b, height_scale)


func _parcel(b, ox: float, oz: float, w: float, d: float, yaw: float, kind: String, h: float) -> Dictionary:
	return {
		"x": b.x + ox, "z": b.z + oz, "w": maxf(2.0, w), "d": maxf(2.0, d),
		"yaw": yaw, "kind": kind, "h": h,
	}


func _tower_parcels(b, height_scale: float, downtown: bool) -> Array:
	# One coherent tower per block, inset so it never touches the sidewalk,
	# with an occasional second, shorter wing sharing the block.
	var inset := 1.4
	var w: float = b.w - inset * 2.0
	var d: float = b.d - inset * 2.0
	if w < 6.0 or d < 6.0:
		return []
	var base := (34.0 if downtown else 15.0) * height_scale
	var h := base + rng.randf_range(0.0, base * 0.55)
	var out := [_parcel(b, 0.0, 0.0, w, d, 0.0, K_TOWER if downtown else K_MIDRISE, h)]
	if w > 26.0 and rng.randf() < 0.6:
		var wing_w := w * 0.34
		out.append(_parcel(b, -(w - wing_w) * 0.5 - inset * 0.2, 0.0,
			wing_w, d * 0.62, 0.0, K_MIDRISE, h * 0.45))
	return out


func _industrial_parcels(b, height_scale: float) -> Array:
	var out: Array = []
	var yard := 6.0
	var w: float = b.w - yard * 2.0
	var d: float = b.d - yard * 2.0
	if w < 8.0 or d < 8.0:
		return []
	var h := rng.randf_range(6.0, 10.0) * maxf(0.6, height_scale)
	out.append(_parcel(b, 0.0, -yard * 0.5, w, d * 0.62, 0.0, K_SHED, h))
	if rng.randf() < 0.5:
		out.append(_parcel(b, w * 0.3, d * 0.34, w * 0.22, d * 0.2, 0.0, K_STACK, h + rng.randf_range(6.0, 14.0)))
	return out


func _suburban_parcels(b) -> Array:
	# Two to four detached houses per block, each with its own garden plot.
	var cols := clampi(roundi(b.w / 15.0), 1, 3)
	var rows := clampi(roundi(b.d / 17.0), 1, 2)
	var cw: float = b.w / float(cols)
	var cd: float = b.d / float(rows)
	var out: Array = []
	for c in cols:
		for r in rows:
			var ox: float = -b.w * 0.5 + cw * (c + 0.5)
			var oz: float = -b.d * 0.5 + cd * (r + 0.5)
			var hw: float = minf(cw * 0.55, 9.5)
			var hd: float = minf(cd * 0.5, 8.5)
			var h := rng.randf_range(3.4, 4.9)
			out.append(_parcel(b, ox, oz, hw, hd, 0.0, K_HOUSE, h))
	return out


func _residential_parcels(b, height_scale: float) -> Array:
	# A villa fits only on a generous plot; tighter blocks become a row of
	# narrow street houses along the block edges instead.
	if b.w >= 27.0 and b.d >= 27.0 and rng.randf() < 0.62:
		return [_parcel(b, 0.0, 0.0, minf(b.w - 4.0, 30.0), minf(b.d - 4.0, 30.0), 0.0,
			K_VILLA, rng.randf_range(4.0, 5.6) * maxf(0.7, height_scale))]
	var out: Array = []
	var rows := 2 if b.d >= 20.0 else 1
	var row_d: float = b.d / float(rows)
	for r in rows:
		var length: float = b.w - 2.0
		var count: int = clampi(roundi(length / 7.0), 1, 6)
		var unit: float = length / float(count)
		var oz: float = -b.d * 0.5 + row_d * (r + 0.5)
		for c in count:
			var ox: float = -length * 0.5 + unit * (c + 0.5)
			var depth: float = minf(row_d * 0.8, 11.0)
			var h := rng.randf_range(7.0, 14.0) * maxf(0.6, height_scale)
			out.append(_parcel(b, ox, oz, unit - 0.9, depth, 0.0, K_ROWHOUSE, h))
	return out


# --------------------------------------------------------- 8. streetscape

## Lamps along every street, crossings at the junctions, trees in the verges
## and a thin scatter of benches, bins and bus stops. All of it is positioned
## from the plan's own street lines, so the furniture always follows the city
## the seed actually produced.
func _stage_streetscape() -> void:
	for v in x_lines:
		var w: float = x_width.get(v, profile.street_w)
		_scatter_along(v, true, w)
	for v in z_lines:
		var w: float = z_width.get(v, profile.street_w)
		_scatter_along(v, false, w)


func _scatter_along(coord: float, along_x: bool, width: float) -> void:
	if _in_reserved_strip(coord, not along_x) and absf(coord - river_cx) < river_corridor:
		return
	var cross: Array[float] = z_lines if along_x else x_lines
	var reach: float = EXTENT - 6.0
	var offset: float = width * 0.5 + 1.6
	for c in cross:
		if absf(c) > reach:
			continue
		var px: float = coord + offset if along_x else c
		var pz: float = c if along_x else coord + offset
		if absf(px) > reach or absf(pz) > reach:
			continue
		if not _blocked_ground(px, pz):
			lamps.append(Vector2(px, pz))
		if absf(fmod(absf(c), profile.pitch * 2.0)) < 0.6:
			crossings.append({"x": coord, "z": c, "horizontal": not along_x})
	# Street trees and small furniture between lamps, on the far verge.
	var gap: float = profile.pitch * 0.5
	var t: float = -reach + gap
	var index := 0
	while t < reach:
		var px2: float = t if along_x else coord - offset
		var pz2: float = coord - offset if along_x else t
		if absf(px2) <= reach and absf(pz2) <= reach and not _blocked_ground(px2, pz2):
			if rng.randf() < 0.55:
				trees.append({"x": px2, "z": pz2,
					"kind": "palm" if rng.randf() < 0.7 else "leafy"})
			elif rng.randf() < 0.35:
				var kinds := ["bench", "bin", "bus_stop", "planter"]
				props.append({"kind": kinds[rng.randi() % kinds.size()],
					"x": px2, "z": pz2, "yaw": 0.0 if along_x else PI * 0.5})
		t += gap
		index += 1


func _on_carriageway(x: float, z: float) -> bool:
	var dx := _nearest_line(x_lines, x)
	var dz := _nearest_line(z_lines, z)
	if dx < _width_at(x_lines, x, x_width) * 0.5 + 0.8:
		return true
	if dz < _width_at(z_lines, z, z_width) * 0.5 + 0.8:
		return true
	return false


## True where street furniture may not stand: inside a reserved estate or the
## landmark plaza, over the open canal corridor, or on a vehicle carriageway.
func _blocked_ground(x: float, z: float) -> bool:
	if _in_any_reserved(x, z):
		return true
	if absf(x - river_cx) < river_corridor + 3.0:
		return true
	return _on_carriageway(x, z)


func _width_at(lines: Array[float], v: float, widths: Dictionary) -> float:
	var best := INF
	var bw: float = profile.street_w
	for l in lines:
		var dd: float = absf(l - v)
		if dd < best:
			best = dd
			bw = widths.get(l, profile.street_w)
	return bw


# ---------------------------------------------------------------- helpers

var _alley_coords: Dictionary = {}


func _unique_sorted(values: Array) -> Array[float]:
	var out: Array[float] = []
	var sorted := values.duplicate()
	sorted.sort()
	for v in sorted:
		var fv: float = float(v)
		if out.is_empty() or absf(out[out.size() - 1] - fv) > 0.25:
			out.append(fv)
	return out


func block_at(x: float, z: float) -> Dictionary:
	for b in blocks:
		if x >= float(b.x0) and x < float(b.x1) and z >= float(b.z0) and z < float(b.z1):
			return b
	return {}
