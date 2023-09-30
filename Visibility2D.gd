extends Node
class_name Visibility2D

# Based on: https://www.redblobgames.com/articles/visibility/Visibility.hx

# Limitations:
# - Segments cant intersect each other, splitting is required for such cases.

const SHORTENING = 0.01

# todo: Make it extend plain object, handle lifetime manually.
class EndPoint:
    var point: Vector2
    var begin: bool
    var segment: int
    var angle: float

    static func sort(p_a: EndPoint, p_b: EndPoint) -> bool:
        if p_a.angle > p_b.angle: return true
        elif p_a.angle < p_b.angle: return false
        elif not p_a.begin and p_b.begin: return true
        else: return false

var _endpoints: Array # of EndPoint
var _sorted_endpoints: Array # of EndPoint
var _open: PoolIntArray # of Segment indices

var center: Vector2
var output: PoolVector2Array

func init_builder() -> Builder:
    _endpoints.resize(0)
    var result := Builder.new()
    result.target = self
    return result

# todo: Ability to cache builder state for static geometry.
class Builder:
    var target: Node

    func view_point(p_point: Vector2) -> Builder:
        target.center = p_point
        return self

    # todo: Use it to cull out endpoints out of working region.
    func bounds(p_area: Rect2) -> Builder:
        target._add_segment(p_area.position, Vector2(p_area.end.x, p_area.position.y))
        target._add_segment(Vector2(p_area.end.x, p_area.position.y), p_area.end)
        target._add_segment(p_area.end, Vector2(p_area.position.x, p_area.end.y))
        target._add_segment(Vector2(p_area.position.x, p_area.end.y), p_area.position)
        return self

    func line(p_line: Line2D) -> Builder:
        for i in range(0, p_line.points.size() - 1):
            target._add_segment(p_line.position + p_line.points[i],
                p_line.position + p_line.points[i + 1])
        return self

    func polygon(p_polygon: Polygon2D) -> Builder:
        var points := p_polygon.polygon
        for i in range(0, points.size() - 1):
            target._add_segment(p_polygon.position + points[i],
                p_polygon.position + points[i + 1])
        target._add_segment(p_polygon.position + points[points.size() - 1],
            p_polygon.position + points[0])
        return self

    func occluder(p_object: Object) -> Builder:
        if p_object is Line2D:
            return line(p_object)
        elif p_object is Polygon2D:
            return polygon(p_object)
        else:
            push_error("Unknown occluder type")
            return self

    func finalize():
        target._finalize()

func _add_segment(p_point0: Vector2, p_point1: Vector2):
    var point0 := EndPoint.new()
    var point1 := EndPoint.new()
    point0.segment = _endpoints.size()
    point1.segment = _endpoints.size()
    point0.point = p_point0
    point1.point = p_point1
    _endpoints.append(point0)
    _endpoints.append(point1)

func _finalize():
    # todo: Only needs to be done when endpoints or center is changed.
    for segment in range(0, _endpoints.size(), 2):
        var p1 := _endpoints[segment] as EndPoint
        var p2 := _endpoints[segment + 1] as EndPoint
        p1.angle = (p1.point - center).angle()
        p2.angle = (p2.point - center).angle()
        # todo: Simplify to one expression.
        var da := p2.angle - p1.angle
        if da <= PI: da += TAU
        if da > PI: da -= TAU
        p1.begin = da > 0.0
        p2.begin = not p1.begin
        # todo: Problem with this is that geometry cannot be cached this way.
        #       We can instead apply a constant that is deterministically reversible.
        p1.point = p1.point.linear_interpolate(p2.point, SHORTENING)
        p2.point = p2.point.linear_interpolate(p1.point, SHORTENING)

func _is_segment_in_front(p_segment1: int, p_segment2: int) -> bool:
    var s1p1 := _endpoints[p_segment1].point as Vector2
    var s1p2 := _endpoints[p_segment1 + 1].point as Vector2
    var s2p1 := _endpoints[p_segment2].point as Vector2
    var s2p2 := _endpoints[p_segment2 + 1].point as Vector2

    # todo: Can we use something simpler than interpolation?
    var d := s1p2 - s1p1
    var a1 := (d.x * (s2p1.y - s1p1.y) \
             - d.y * (s2p1.x - s1p1.x)) < 0.0
    var a2 := (d.x * (s2p2.y - s1p1.y) \
             - d.y * (s2p2.x - s1p1.x)) < 0.0
    var a3 := (d.x * (center.y - s1p1.y) \
             - d.y * (center.x - s1p1.x)) < 0.0

    if a1 == a2 and a2 == a3: return true

    d = s2p2 - s2p1
    var b1 := (d.x * (s1p1.y - s2p1.y) \
             - d.y * (s1p1.x - s2p1.x)) < 0.0
    var b2 := (d.x * (s1p2.y - s2p1.y) \
             - d.y * (s1p2.x - s2p1.x)) < 0.0
    var b3 := (d.x * (center.y - s2p1.y) \
             - d.y * (center.x - s2p1.x)) < 0.0

    return b1 == b2 and b2 != b3

func sweep() -> PoolVector2Array:
    output.resize(0)
    # todo: Only duplicate and sort on change.
    _sorted_endpoints = _endpoints.duplicate()
    _sorted_endpoints.sort_custom(EndPoint, "sort")

    var start_angle := 0.0

    # todo: Inline passes.
    for n_pass in range(2):
        for p_idx in range(_sorted_endpoints.size() - 1, -1, -1):
            var p := _sorted_endpoints[p_idx] as EndPoint
            var old := -1 if _open.empty() else _open[0]

            if p.begin:
                var idx := 0
                while idx < _open.size() and _is_segment_in_front(p.segment, _open[idx]):
                    idx += 1
                # warning-ignore:return_value_discarded
                _open.insert(idx, p.segment)
            else:
                var idx := _open.rfind(p.segment)
                if idx != -1: _open.remove(idx)
                # todo: Second pass can assume that it will be found.
                # _open.remove(_open.rfind(p.segment))

            if old != (-1 if _open.empty() else _open[0]):
                if n_pass == 1:
                    # todo: Distance should be configurable.
                    var p3 := _endpoints[old].point as Vector2 if old != -1 else \
                        center + Vector2(cos(start_angle), sin(start_angle)) * 500.0
                    var t2 := Vector2(cos(p.angle), sin(p.angle))
                    var p4 := p3.direction_to(_endpoints[old + 1].point) if old != -1 else t2 

                    var l = Geometry.line_intersects_line_2d(p3, p4, center,
                        Vector2(cos(start_angle), sin(start_angle)))
                    if l != null: output.append(l)
                    l = Geometry.line_intersects_line_2d(p3, p4, center, t2)
                    if l != null: output.append(l)

                start_angle = p.angle

    _open.resize(0)

    return output
