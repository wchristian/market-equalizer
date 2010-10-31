function stack( data, start, end, min, max ) {

    var w = 400,
    h = 200,
    x = pv.Scale.
        linear(start, end).
        range(0, w),
    y = pv.Scale.
        linear(min, max).
        range(0, h);

    /* The root panel. */
    var vis = new pv.Panel()
        .width(w)
        .height(h)
        .bottom(20)
        .left(40)
        .right(10)
        .top(5);

    /* X-axis ticks. */
    vis.add(pv.Rule)
        .data(x.ticks())
        .visible(function(d) d > 0)
        .left(x)
        .strokeStyle("#eee")
      .add(pv.Rule)
        .bottom(-5)
        .height(5)
        .strokeStyle("#000")
      .anchor("bottom").add(pv.Label)
        .text(x.tickFormat);

    /* Y-axis ticks. */
    vis.add(pv.Rule)
        .data(y.ticks(5))
        .bottom(y)
        .strokeStyle(function(d) d ? "#eee" : "#000")
      .anchor("left").add(pv.Label)
        .text(y.tickFormat);

    /* The line. */
    vis.add(pv.Line)
        .data(data)
        .interpolate("step-after")
        .left(function(d) x(d.x))
        .bottom(function(d) y(d.y))
        .lineWidth(3);

    vis.render();
}
