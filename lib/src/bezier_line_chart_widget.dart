import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'bezier_line.dart';
import 'bezier_line_chart_config.dart';
import 'package:intl/intl.dart' as intl;

class BezierLineChart extends StatefulWidget {
  final BezierLineChartConfig config;

  ///Type of Chart
  final BezierLineChartScale bezierLineChartScale;

  ///This value is required only if the `bezierLineChartScale` is `BezierLineChartScale.CUSTOM`
  ///and these values must be sorted in increasing way (These will be showed in the Axis X).
  final List<double> xAxisCustomValues;

  ///This value is required only if the `bezierLineChartScale` is not `BezierLineChartScale.CUSTOM`
  final DateTime fromDate;

  ///This value is required only if the `bezierLineChartScale` is not `BezierLineChartScale.CUSTOM`
  final DateTime toDate;

  ///This value represents the date selected to display the info in the Chart
  ///For `BezierLineChartScale.WEEKLY` it will use year, month and day
  ///For `BezierLineChartScale.MONTHLY` it will use year, month
  ///For `BezierLineChartScale.YEARLY` it will use year
  final DateTime selectedDate;

  ///Beziers used in the Axis Y
  final List<BezierLine> series;

  BezierLineChart({
    Key key,
    this.config,
    this.xAxisCustomValues,
    this.fromDate,
    this.toDate,
    this.selectedDate,
    @required this.bezierLineChartScale,
    @required this.series,
  })  : assert(
          (bezierLineChartScale == BezierLineChartScale.CUSTOM &&
                  xAxisCustomValues != null &&
                  series != null) ||
              bezierLineChartScale != BezierLineChartScale.CUSTOM,
          "The xAxisCustomValues and series must not be null",
        ),
        assert(
          bezierLineChartScale == BezierLineChartScale.CUSTOM &&
                  _isSorted(xAxisCustomValues) ||
              bezierLineChartScale != BezierLineChartScale.CUSTOM,
          "The xAxisCustomValues must be sorted in increasing way",
        ),
        assert(
          bezierLineChartScale == BezierLineChartScale.CUSTOM &&
                  _compareLengths(xAxisCustomValues.length, series) ||
              bezierLineChartScale != BezierLineChartScale.CUSTOM,
          "xAxisCustomValues lenght must be equals to series length",
        ),
        assert(
          (bezierLineChartScale == BezierLineChartScale.CUSTOM &&
                  _allPositive(xAxisCustomValues) &&
                  _checkCustomValues(series)) ||
              bezierLineChartScale != BezierLineChartScale.CUSTOM,
          "xAxisCustomValues and series must be positives",
        ),
        assert(
          (((bezierLineChartScale != BezierLineChartScale.CUSTOM) &&
                  fromDate != null &&
                  toDate != null) ||
              (bezierLineChartScale == BezierLineChartScale.CUSTOM &&
                  fromDate == null &&
                  toDate == null)),
          "fromDate and toDate must not be null",
        ),
        assert(
          (((bezierLineChartScale != BezierLineChartScale.CUSTOM) &&
                  toDate.isAfter(fromDate)) ||
              (bezierLineChartScale == BezierLineChartScale.CUSTOM &&
                  fromDate == null &&
                  toDate == null)),
          "toDate must be after of fromDate",
        ),
        super(key: key);

  @override
  _BezierLineChartState createState() => _BezierLineChartState();
}

class _BezierLineChartState extends State<BezierLineChart>
    with SingleTickerProviderStateMixin {
  Offset _verticalIndicatorPosition;
  bool _displayIndicator = false;
  AnimationController _animationController;
  ScrollController _scrollController;
  //padding for leading and trailing of the chart
  final double horizontalPadding = 50.0;
  //spacing between each datapoint
  double horizontalSpacing = 60.0;
  List<DataPoint> _xAxisDataPoints = [];
  GlobalKey _keyScroll = GlobalKey();
  List<BezierLine> computedSeries = [];
  double _currentScale = 1.0;
  double _previousScale;
  BezierLineChartScale _currentBezierLineChartScale;
  double _lastValueSnapped = double.infinity;
  bool get isPinchZoomActive => _touchFingers > 1;
  bool get isOnlyOneAxis => _xAxisDataPoints.length <= 1;

  _refreshPosition(details) {
    if (_animationController.status == AnimationStatus.completed &&
        _displayIndicator) {
      _updatePosition(details);
    }
  }

  _updatePosition(details) {
    setState(
      () {
        RenderBox renderBox = context.findRenderObject();
        final position = renderBox.globalToLocal(details.globalPosition);

        if (position != null) {
          final fixedPosition = Offset(
              position.dx + _scrollController.offset - horizontalPadding,
              position.dy);
          _verticalIndicatorPosition = fixedPosition;
        }
      },
    );
  }

  _onDisplayIndicator(details) {
    if (!_displayIndicator) {
      _displayIndicator = true;
      _animationController.forward(
        from: 0.0,
      );
    }
    _onDataPointSnap(double.maxFinite);
    _updatePosition(details);
  }

  _onHideIndicator() {
    if (_displayIndicator) {
      setState(
        () {
          _displayIndicator = false;
        },
      );
    }
  }

  void _onDataPointSnap(double value) {
    if (_lastValueSnapped != value && widget.config.snap) {
      if (Platform.isIOS) {
        HapticFeedback.heavyImpact();
      } else {
        Feedback.forTap(context);
      }
      _lastValueSnapped = value;
    }
  }

  void _buildXDataPoints() {
    _xAxisDataPoints = [];
    final scale = _currentBezierLineChartScale;
    if (scale == BezierLineChartScale.CUSTOM) {
      _xAxisDataPoints = widget.xAxisCustomValues
          .map((val) => DataPoint<double>(value: val, xAxis: val))
          .toList();
    } else if (scale == BezierLineChartScale.WEEKLY) {
      final days = widget.toDate.difference(widget.fromDate).inDays;
      for (int i = 0; i < days; i++) {
        final newDate = widget.fromDate.add(
          Duration(
            days: (i + 1),
          ),
        );
        _xAxisDataPoints.add(
          DataPoint<DateTime>(value: (i * 5).toDouble(), xAxis: newDate),
        );
      }
    } else if (scale == BezierLineChartScale.MONTHLY) {
      DateTime startDate = DateTime(
        widget.fromDate.year,
        widget.fromDate.month,
      );
      DateTime endDate = DateTime(
        widget.toDate.year,
        widget.toDate.month,
      );
      for (int i = 0;
          (startDate.isBefore(endDate) || areEqualDates(startDate, endDate));
          i++) {
        _xAxisDataPoints.add(
          DataPoint<DateTime>(value: (i * 5).toDouble(), xAxis: startDate),
        );
        startDate = DateTime(startDate.year, startDate.month + 1);
      }
    } else if (scale == BezierLineChartScale.YEARLY) {
      DateTime startDate = DateTime(
        widget.fromDate.year,
      );
      DateTime endDate = DateTime(
        widget.toDate.year,
      );
      for (int i = 0;
          (startDate.isBefore(endDate) || areEqualDates(startDate, endDate));
          i++) {
        _xAxisDataPoints.add(
          DataPoint<DateTime>(value: (i * 5).toDouble(), xAxis: startDate),
        );
        startDate = DateTime(
          startDate.year + 1,
        );
      }
    }
  }

  double _buildContentWidth(BoxConstraints constraints) {
    final scale = _currentBezierLineChartScale;
    if (scale == BezierLineChartScale.CUSTOM) {
      return widget.config.contentWidth ??
          constraints.maxWidth - horizontalPadding;
    } else {
      if (scale == BezierLineChartScale.WEEKLY) {
        horizontalSpacing = constraints.maxWidth / 7;
        return _xAxisDataPoints.length * (horizontalSpacing * _currentScale) -
            horizontalPadding / 2;
      } else if (scale == BezierLineChartScale.MONTHLY) {
        horizontalSpacing = constraints.maxWidth / 12;
        return _xAxisDataPoints.length * (horizontalSpacing * _currentScale) -
            horizontalPadding / 2;
      } else if (scale == BezierLineChartScale.YEARLY) {
        if (_xAxisDataPoints.length > 12) {
          horizontalSpacing = constraints.maxWidth / 12;
        } else if (_xAxisDataPoints.length < 6) {
          horizontalSpacing = constraints.maxWidth / 6;
        } else {
          horizontalSpacing = constraints.maxWidth / _xAxisDataPoints.length;
        }
        return _xAxisDataPoints.length * (horizontalSpacing * _currentScale) -
            horizontalPadding;
      }
      return 0.0;
    }
  }

  _onLayoutDone(_) {
    //Move to selected position
    if (widget.selectedDate != null) {
      int index = -1;
      if (_currentBezierLineChartScale == BezierLineChartScale.WEEKLY) {
        index = _xAxisDataPoints.indexWhere(
            (dp) => areEqualDates((dp.xAxis as DateTime), widget.selectedDate));
      } else if (_currentBezierLineChartScale == BezierLineChartScale.MONTHLY) {
        index = _xAxisDataPoints.indexWhere((dp) =>
            (dp.xAxis as DateTime).year == widget.selectedDate.year &&
            (dp.xAxis as DateTime).month == widget.selectedDate.month);
      } else if (_currentBezierLineChartScale == BezierLineChartScale.YEARLY) {
        index = _xAxisDataPoints.indexWhere(
            (dp) => (dp.xAxis as DateTime).year == widget.selectedDate.year);
      }

      if (index >= 0) {
        final jumpToX = (index * horizontalSpacing) -
            horizontalPadding / 2 -
            _keyScroll.currentContext.size.width / 2;
        _scrollController.jumpTo(jumpToX);

        final fixedPosition = Offset(
            isOnlyOneAxis
                ? 0.0
                : (index * horizontalSpacing + 2 * horizontalPadding) -
                    _scrollController.offset,
            0.0);

        _verticalIndicatorPosition = fixedPosition;
        _onDisplayIndicator(
          LongPressMoveUpdateDetails(
            globalPosition: fixedPosition,
            offsetFromOrigin: fixedPosition,
          ),
        );
      }
    }
  }

  _computeSeries() {
    computedSeries = [];
    //fill data series for DateTime scale type
    if (_currentBezierLineChartScale == BezierLineChartScale.MONTHLY ||
        _currentBezierLineChartScale == BezierLineChartScale.YEARLY) {
      for (BezierLine line in widget.series) {
        Map<String, double> valueMap = Map();
        for (DataPoint<DateTime> dataPoint in line.data) {
          String key;

          if (_currentBezierLineChartScale == BezierLineChartScale.MONTHLY) {
            key =
                "${dataPoint.xAxis.year},${dataPoint.xAxis.month.toString().padLeft(2, '0')}";
          } else {
            key = "${dataPoint.xAxis.year}";
          }

          if (valueMap.containsKey(key)) {
            final value = valueMap[key];
            valueMap[key] = value + dataPoint.value;
          } else {
            valueMap[key] = dataPoint.value;
          }
        }

        List<DataPoint<DateTime>> newDataPoints = [];
        valueMap.keys.forEach(
          (key) {
            if (_currentBezierLineChartScale == BezierLineChartScale.MONTHLY) {
              List<String> split = key.split(",");
              int year = int.parse(split[0]);
              int month = int.parse(split[1]);
              newDataPoints.add(
                DataPoint<DateTime>(
                  value: valueMap[key],
                  xAxis: DateTime(year, month),
                ),
              );
            } else {
              int year = int.parse(key);
              newDataPoints.add(
                DataPoint<DateTime>(
                  value: valueMap[key],
                  xAxis: DateTime(year),
                ),
              );
            }
          },
        );

        BezierLine newBezierLine = BezierLine.copy(
          bezierLine: BezierLine(
            lineColor: line.lineColor,
            label: line.label,
            lineStrokeWidth: line.lineStrokeWidth,
            onMissingValue: line.onMissingValue,
            data: newDataPoints,
          ),
        );
        computedSeries.add(newBezierLine);
      }
    } else {
      computedSeries = widget.series;
    }
  }

  _onPinchZoom(double scale) {
    scale = double.parse(scale.toStringAsFixed(1));
    if (isPinchZoomActive) {
      if (scale < 1) {
        if (_currentBezierLineChartScale == BezierLineChartScale.WEEKLY) {
          _currentBezierLineChartScale = BezierLineChartScale.MONTHLY;
          _previousScale = 1.5;
        } else if (_currentBezierLineChartScale ==
            BezierLineChartScale.MONTHLY) {
          _currentBezierLineChartScale = BezierLineChartScale.YEARLY;
        }
        _currentScale = 1.0;
        setState(
          () {
            _buildXDataPoints();
            _computeSeries();
          },
        );
        return;
      } else if (scale > 1.5 || (isOnlyOneAxis && scale > 1.2)) {
        if (_currentBezierLineChartScale == BezierLineChartScale.YEARLY) {
          _currentBezierLineChartScale = BezierLineChartScale.MONTHLY;
          _currentScale = 1.0;
          _previousScale = 1.0;
          setState(
            () {
              _buildXDataPoints();
              _computeSeries();
            },
          );
        } else if (_currentBezierLineChartScale ==
            BezierLineChartScale.MONTHLY) {
          _currentBezierLineChartScale = BezierLineChartScale.WEEKLY;
          _currentScale = 1.0;
          _previousScale = 1.0;
          setState(
            () {
              _buildXDataPoints();
              _computeSeries();
            },
          );
          return;
        }
      } else {
        if (scale > 2.5) scale = 2.5;
        if (scale != _currentScale) {
          setState(
            () {
              _currentScale = scale;
            },
          );
        }
      }
    }
  }

  @override
  void initState() {
    _currentBezierLineChartScale = widget.bezierLineChartScale;
    _scrollController = ScrollController();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 150),
    );
    _buildXDataPoints();
    _computeSeries();
    WidgetsBinding.instance.addPostFrameCallback(_onLayoutDone);
    super.initState();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int _touchFingers = 0;

  @override
  Widget build(BuildContext context) {
    //using `Listener` to fix the issue with single touch for multitouch gesture like pinch/zoom
    //https://github.com/flutter/flutter/issues/13102
    return Container(
      decoration: BoxDecoration(
        color: widget.config.backgroundGradient != null
            ? null
            : widget.config.backgroundColor,
        gradient: widget.config.backgroundGradient,
      ),
      child: Listener(
        onPointerDown: (_) {
          _touchFingers++;
          if (_touchFingers > 1) {
            setState(() {});
          }
        },
        onPointerUp: (_) {
          _touchFingers--;
          if (_touchFingers < 2) {
            setState(() {});
          }
        },
        child: GestureDetector(
          onLongPressStart: isPinchZoomActive ? null : _onDisplayIndicator,
          onLongPressMoveUpdate: isPinchZoomActive ? null : _refreshPosition,
          onScaleStart: (_) {
            _previousScale = _currentScale;
          },
          onScaleUpdate:
              _currentBezierLineChartScale != BezierLineChartScale.CUSTOM &&
                      !_displayIndicator
                  ? (details) {
                      _onPinchZoom(_previousScale * details.scale);
                    }
                  : null,
          onTap: isPinchZoomActive ? null : _onHideIndicator,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _scrollController,
                physics: isPinchZoomActive
                    ? NeverScrollableScrollPhysics()
                    : AlwaysScrollableScrollPhysics(),
                key: _keyScroll,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Align(
                  alignment: Alignment(0.0, 0.7),
                  child: CustomPaint(
                    size: Size(
                      _buildContentWidth(constraints),
                      constraints.biggest.height * 0.7,
                    ),
                    painter: _BezierLineChartPainter(
                      config: widget.config,
                      bezierLineChartScale: _currentBezierLineChartScale,
                      verticalIndicatorPosition: _verticalIndicatorPosition,
                      series: computedSeries,
                      showIndicator: _displayIndicator,
                      animation: _animationController,
                      xAxisDataPoints: _xAxisDataPoints,
                      onDataPointSnap: _onDataPointSnap,
                      maxWitdth: MediaQuery.of(context).size.width,
                      scrollOffset: _scrollController.positions.isNotEmpty
                          ? _scrollController.offset
                          : 0.0,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

//BezierLineChart
class _BezierLineChartPainter extends CustomPainter {
  final BezierLineChartConfig config;
  final Offset verticalIndicatorPosition;
  final List<BezierLine> series;
  final List<DataPoint> xAxisDataPoints;
  double _maxValueY = 0.0;
  double _maxValueX = 0.0;
  List<_CustomValue> _currentCustomValues = [];
  DataPoint _currentXDataPoint;
  final double radiusDotIndicatorMain = 7;
  final double radiusDotIndicatorItems = 5;
  final bool showIndicator;
  final Animation animation;
  final ValueChanged<double> onDataPointSnap;
  final BezierLineChartScale bezierLineChartScale;
  final double maxWitdth;
  final double scrollOffset;
  bool footerDrawed = false;

  _BezierLineChartPainter({
    this.config,
    this.verticalIndicatorPosition,
    this.series,
    this.showIndicator,
    this.xAxisDataPoints,
    this.animation,
    this.bezierLineChartScale,
    this.onDataPointSnap,
    this.maxWitdth,
    this.scrollOffset,
  }) : super(repaint: animation) {
    _maxValueY = _getMaxValueY();
    _maxValueX = _getMaxValueX();
  }

  double _getMaxValueX() {
    double x = double.negativeInfinity;
    for (double val in xAxisDataPoints.map((dp) => dp.value).toList()) {
      if (val > x) x = val;
    }
    return x;
  }

  double _getMaxValueY() {
    double y = double.negativeInfinity;
    for (BezierLine line in series) {
      for (double val in line.data.map((dp) => dp.value).toList()) {
        if (val > y) y = val;
      }
    }
    return y;
  }

  _getRealValue(double value, double maxConstraint, double maxValue) =>
      maxConstraint * value / (maxValue == 0 ? 1 : maxValue);

  @override
  void paint(Canvas canvas, Size size) {
    //print("CANVAS size: $size ..");
    final height = size.height - config.footerHeight;
    Paint paintVerticalIndicator = Paint()
      ..color = config.verticalIndicatorColor
      ..strokeWidth = config.verticalIndicatorStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    Paint paintControlPoints = Paint()..strokeCap = StrokeCap.round;

    //fixing verticalIndicator outbounds
    double verticalX = 0.0;

    if (verticalIndicatorPosition != null) {
      verticalX = verticalIndicatorPosition.dx;
      if (verticalIndicatorPosition.dx < 0) {
        verticalX = 0.0;
      } else if (verticalIndicatorPosition.dx > size.width) {
        verticalX = size.width;
      }
    }

    //axisValues.sort((val1, val2) => (val1.x > val2.x) ? 1 : -1);

    //variables for the last item on the list (this is required to display the indicator)
    Offset p0, p1, p2, p3;
    void _drawBezierLinePath(BezierLine line) {
      Path path = Path();
      List<Offset> dataPoints = [];

      TextPainter textPainterFooter = TextPainter(
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );

      TextStyle styleFooter = TextStyle(
        color: config.footerColor,
        fontWeight: FontWeight.w400,
        fontSize: 12,
      );

      Paint paintLine = Paint()
        ..color = line.lineColor
        ..strokeWidth = line.lineStrokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      _AxisValue lastPoint = _AxisValue(
        x: 0,
        y: height,
      );
      path.moveTo(0, height);

      for (int i = 0; i < xAxisDataPoints.length; i++) {
        double value = 0.0;

        double axisX = xAxisDataPoints[i].value;

        final double valueX = _getRealValue(
          axisX,
          size.width,
          _maxValueX,
        );

        //only calculate and display the necessary data to improve the performance of the scrolling
        final range = maxWitdth * 10;
        if (scrollOffset - range >= valueX || scrollOffset + range <= valueX) {
          continue;
        }

        if (bezierLineChartScale == BezierLineChartScale.CUSTOM) {
          value = line.data[i].value;
        } else {
          //search from axis
          for (DataPoint<DateTime> dp in line.data) {
            final dateTime = (xAxisDataPoints[i].xAxis as DateTime);
            if (areEqualDates(dateTime, dp.xAxis)) {
              value = dp.value;
              axisX = xAxisDataPoints[i].value;
              break;
            }
          }

          if (value == 0) {
            if (line.onMissingValue != null) {
              value = line.onMissingValue(xAxisDataPoints[i].xAxis as DateTime);
            }
          }
        }

        final double axisY = value;
        final double valueY = height -
            _getRealValue(
              axisY,
              height,
              _maxValueY,
            );

        final double controlPointX = lastPoint.x + (valueX - lastPoint.x) / 2;
        path.cubicTo(
            controlPointX, lastPoint.y, controlPointX, valueY, valueX, valueY);
        dataPoints.add(Offset(valueX, valueY));

        if (verticalIndicatorPosition != null &&
            verticalX >= lastPoint.x &&
            verticalX <= valueX) {
          //points to draw the info
          p0 = Offset(lastPoint.x, height - lastPoint.y);
          p1 = Offset(controlPointX, height - lastPoint.y);
          p2 = Offset(controlPointX, height - valueY);
          p3 = Offset(valueX, height - valueY);
        }

        if (verticalIndicatorPosition != null) {
          //get current information
          double nextX = double.infinity;
          double lastX = double.negativeInfinity;
          if (xAxisDataPoints.length > (i + 1)) {
            nextX = _getRealValue(
              xAxisDataPoints[i + 1].value,
              size.width,
              _maxValueX,
            );
          }
          if (i > 0) {
            lastX = _getRealValue(
              xAxisDataPoints[i - 1].value,
              size.width,
              _maxValueX,
            );
          }

          if (verticalX >= valueX - (valueX - lastX) / 2 &&
              verticalX <= valueX + (nextX - valueX) / 2) {
            _currentXDataPoint = xAxisDataPoints[i];
            if (_currentCustomValues.length < series.length) {
              onDataPointSnap(xAxisDataPoints[i].value);
              _currentCustomValues.add(
                _CustomValue(
                  value: "${_intOrDouble(axisY)}",
                  label: line.label,
                  color: line.lineColor,
                ),
              );
            }
          }
        }

        lastPoint = _AxisValue(x: valueX, y: valueY);

        //draw footer
        textPainterFooter.text = TextSpan(
          text: _getFooterText(xAxisDataPoints[i]),
          style: styleFooter,
        );

        textPainterFooter.layout(maxWidth: 50.0);
        textPainterFooter.paint(
          canvas,
          Offset(valueX - textPainterFooter.width / 2,
              size.height - textPainterFooter.height / 2),
        );
      }

      if (!footerDrawed) footerDrawed = true;

      canvas.drawPath(path, paintLine);
      if (config.showDataPoints) {
        canvas.drawPoints(
            PointMode.points,
            dataPoints,
            paintControlPoints
              ..style = PaintingStyle.stroke
              ..strokeWidth = 10
              ..color = line.lineColor);
        canvas.drawPoints(
          PointMode.points,
          dataPoints,
          paintControlPoints
            ..style = PaintingStyle.fill
            ..strokeWidth = line.lineStrokeWidth * 1.5
            ..color = config.backgroundColor,
        );
      }
    }

    for (BezierLine line in series.reversed.toList()) {
      _drawBezierLinePath(line);
    }

    if (verticalIndicatorPosition != null && showIndicator) {
      if (config.snap) {
        verticalX = _getRealValue(
          _currentXDataPoint.value,
          size.width,
          _maxValueX,
        );
      }

      if (config.showVerticalIndicator) {
        canvas.drawLine(
          Offset(verticalX, 0),
          Offset(verticalX, height),
          paintVerticalIndicator,
        );
      }

      if (p0 != null) {
        final yValue = _getYValues(
          p0,
          p1,
          p2,
          p3,
          (verticalX - p0.dx) / (p3.dx - p0.dx),
        );

        double infoWidth = 85;
        double infoHeight = 35;

        double offsetInfo =
            infoHeight * 1.2 + ((_currentCustomValues.length - 1.0) * 10.0);
        final centerForCircle = Offset(verticalX, height - yValue);
        final center = config.verticalIndicatorFixedPosition
            ? Offset(verticalX, offsetInfo)
            : centerForCircle;

        //draw point
        canvas.drawCircle(
          centerForCircle,
          radiusDotIndicatorMain,
          Paint()
            ..color = series.reversed.toList().last.lineColor
            ..strokeWidth = 4.0,
        );

        //calculate the total lenght of the lines
        List<TextSpan> textValues = [];
        List<Offset> centerCircles = [];
        double space = 0;
        for (_CustomValue customValue
            in _currentCustomValues.reversed.toList()) {
          infoHeight += 9;
          textValues.add(
            TextSpan(
              text: "${customValue.value} ",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
              children: [
                TextSpan(
                  text: "${customValue.label}\n",
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          );
          centerCircles.add(
            Offset(center.dx - infoWidth / 2 + radiusDotIndicatorItems * 1.5,
                center.dy - offsetInfo - radiusDotIndicatorItems / 2 + space),
          );
          space += 14;
        }

        //draw shadow info
        Path path = Path();
        path.moveTo(center.dx - infoWidth / 2, center.dy - offsetInfo + 5);
        path.lineTo(center.dx + infoWidth / 2, center.dy - offsetInfo + 5);
        path.lineTo(center.dx + infoWidth / 2, center.dy - offsetInfo - 10);
        canvas.drawShadow(path, Colors.black, 20.0, false);

        final paintInfo = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        //draw info
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(
                center.dx,
                center.dy - offsetInfo,
              ),
              width: infoWidth,
              height: infoHeight * animation.value,
            ),
            Radius.circular(5),
          ),
          paintInfo,
        );

        final double trianguleSize = 8;
        Path pathArrow = Path();
        pathArrow.moveTo(
            center.dx - trianguleSize, center.dy - offsetInfo / 2 - 2);
        pathArrow.lineTo(center.dx, center.dy - offsetInfo / 4 - 2);
        pathArrow.lineTo(
            center.dx + trianguleSize, center.dy - offsetInfo / 2 - 2);
        pathArrow.close();
        canvas.drawPath(
          pathArrow,
          paintInfo,
        );
        //end draw info

        //draw Text
        TextPainter textPainter = TextPainter(
          textAlign: TextAlign.center,
          text: TextSpan(
            text: _getInfoTitleText(),
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            children: textValues,
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
              center.dx -
                  textPainter.size.width / 2 +
                  radiusDotIndicatorItems * 1.5,
              center.dy - offsetInfo - infoHeight / 2.5),
        );

        //draw circle indicators
        for (int z = 0; z < _currentCustomValues.length; z++) {
          _CustomValue customValue = _currentCustomValues[z];
          Offset centerIndicator = centerCircles.reversed.toList()[z];
          canvas.drawCircle(
              centerIndicator,
              radiusDotIndicatorItems,
              Paint()
                ..color = customValue.color
                ..style = PaintingStyle.fill);
          canvas.drawCircle(
              centerIndicator,
              radiusDotIndicatorItems,
              Paint()
                ..color = Colors.black
                ..strokeWidth = 0.5
                ..style = PaintingStyle.stroke);
        }
      }
    }
  }

  String _getInfoTitleText() {
    final scale = bezierLineChartScale;
    if (scale == BezierLineChartScale.CUSTOM) {
      return "${_intOrDouble(_currentXDataPoint.value)}\n";
    } else if (scale == BezierLineChartScale.WEEKLY) {
      final dateFormat = intl.DateFormat('EEE d');
      final date = _currentXDataPoint.xAxis as DateTime;
      final now = DateTime.now();
      if (areEqualDates(date, now)) {
        return "Today\n";
      } else {
        return "${dateFormat.format(_currentXDataPoint.xAxis)}\n";
      }
    } else if (scale == BezierLineChartScale.MONTHLY) {
      final dateFormat = intl.DateFormat('MMM y');
      final date = _currentXDataPoint.xAxis as DateTime;
      final now = DateTime.now();
      if (date.year == now.year && now.month == date.month) {
        return "Current Month\n";
      } else {
        return "${dateFormat.format(_currentXDataPoint.xAxis)}\n";
      }
    } else if (scale == BezierLineChartScale.YEARLY) {
      final dateFormat = intl.DateFormat('y');
      final date = _currentXDataPoint.xAxis as DateTime;
      final now = DateTime.now();
      if (date.year == now.year) {
        return "Current Year\n";
      } else {
        return "${dateFormat.format(_currentXDataPoint.xAxis)}\n";
      }
    }
    return "";
  }

  String _getFooterText(DataPoint dataPoint) {
    final scale = bezierLineChartScale;
    if (scale == BezierLineChartScale.CUSTOM) {
      return "${_intOrDouble(dataPoint.value)}\n";
    } else if (scale == BezierLineChartScale.WEEKLY) {
      final dateFormat = intl.DateFormat('EEE\nd');
      return "${dateFormat.format(dataPoint.xAxis as DateTime)}";
    } else if (scale == BezierLineChartScale.MONTHLY) {
      final dateFormat = intl.DateFormat('MMM');
      final dateFormatYear = intl.DateFormat('y');
      final year =
          dateFormatYear.format(dataPoint.xAxis as DateTime).substring(2);
      return "${dateFormat.format(dataPoint.xAxis as DateTime)}\n'$year";
    } else if (scale == BezierLineChartScale.YEARLY) {
      final dateFormat = intl.DateFormat('y');
      return "${dateFormat.format(dataPoint.xAxis as DateTime)}";
    }
    return "";
  }

  _getYValues(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    if (t.isNaN) {
      t = 1.0;
    }
    //P0 = (X0,Y0)
    //P1 = (X1,Y1)
    //P2 = (X2,Y2)
    //P3 = (X3,Y3)
    //X(t) = (1-t)^3 * X0 + 3*(1-t)^2 * t * X1 + 3*(1-t) * t^2 * X2 + t^3 * X3
    //Y(t) = (1-t)^3 * Y0 + 3*(1-t)^2 * t * Y1 + 3*(1-t) * t^2 * Y2 + t^3 * Y3
    //source: https://stackoverflow.com/questions/8217346/cubic-bezier-curves-get-y-for-given-x
    final x0 = p0.dx, y0 = p0.dy;
    final x1 = p1.dx, y1 = p1.dy;
    final x2 = p2.dx, y2 = p2.dy;
    final x3 = p3.dx, y3 = p3.dy;

    //print("p0: $p0, p1: $p1, p2: $p2, p3: $p3 , t: $t");

    final y = pow(1 - t, 3) * y0 +
        3 * pow(1 - t, 2) * t * y1 +
        3 * (1 - t) * pow(t, 2) * y2 +
        pow(t, 3) * y3;
    return y;
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class _AxisValue {
  final double x;
  final double y;
  const _AxisValue({
    this.x,
    this.y,
  });
}

bool _compareLengths(int currentValue, List<BezierLine> val2) {
  for (BezierLine line in val2) {
    if (currentValue != line.data.length) {
      return false;
    }
  }
  return true;
}

bool _isSorted<T>(List<double> list, [int Function(double, double) compare]) {
  if (list.length < 2) return true;
  compare ??= (double a, double b) => a.compareTo(b);
  double prev = list.first;
  for (var i = 1; i < list.length; i++) {
    double next = list[i];
    if (compare(prev, next) > 0) return false;
    prev = next;
  }
  return true;
}

bool _checkCustomValues(List<BezierLine> list) {
  for (BezierLine line in list) {
    if (!_allPositive(
      line.data.map((dp) => dp.value).toList(),
    )) return false;
  }
  return true;
}

bool _allPositive(List<double> list) {
  for (double val in list) {
    if (val < 0) return false;
  }
  return true;
}

String _intOrDouble(double str) {
  final values = str.toString().split(".");
  if (values.length > 1) {
    final int intDecimal = int.parse(values[1]);
    if (intDecimal == 0) {
      return str.toInt().toString();
    }
  }
  return str.toString();
}

class _CustomValue {
  final String value;
  final String label;
  final Color color;

  _CustomValue({
    @required this.value,
    @required this.label,
    @required this.color,
  });
}

bool areEqualDates(DateTime dateTime1, DateTime dateTime2) =>
    dateTime1.year == dateTime2.year &&
    dateTime1.month == dateTime2.month &&
    dateTime1.day == dateTime2.day;
