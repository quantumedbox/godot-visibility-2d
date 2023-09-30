Example:
```gdscript
$Visibility2D.init_builder() \
    .view_point(get_global_mouse_position()) \
    .bounds(get_viewport_rect()) \
    .occluder($Line2D) \
    .finalize()

var edges = $Visibility2D.sweep()
for i in range(0, edges.size() - 1, 2):
    var polygon := Polygon2D.new()
    polygon.polygon = PoolVector2Array([$Visibility2D.center, edges[i], edges[i + 1]])
    $Cones.add_child(polygon)
```
