# Demo: Apple "hello" via MCP

This script is meant to be read and executed by an AI agent connected to
ButtonHeist via MCP. The agent should follow each step in order, calling
the listed MCP tools directly.

## Prerequisites

- iOS app with InsideJob running (simulator or device)
- ButtonHeist MCP server connected (tools like `get_screen` are available)

## Script

### 1. Navigate to Touch Canvas

```tool
get_screen
```

If the app is on the main menu, tap "Touch Canvas":

```tool
activate(order: 1)
```

If already on the Touch Canvas, skip this step.

### 2. Clear the canvas

```tool
activate(identifier: "buttonheist.touchCanvas.resetButton")
```

### 3. Draw the Apple "hello"

This is the canonical Apple "hello" script lettering — 48 cubic bezier
curves forming a single continuous pen stroke. The path data comes from
`UIBezierPath+AppleHello.swift`, scaled to fit the Touch Canvas
(x: 18-378, y: 350-547).

```tool
draw_bezier(
  startX: 65.4,
  startY: 458.4,
  segments: [
    {"cp1X": 69.2, "cp1Y": 427.7, "cp2X": 72.9, "cp2Y": 396.9, "endX": 76.7, "endY": 366.2},
    {"cp1X": 78.0, "cp1Y": 359.4, "cp2X": 80.7, "cp2Y": 350.3, "endX": 84.7, "endY": 350.0},
    {"cp1X": 86.1, "cp1Y": 350.0, "cp2X": 87.8, "cp2Y": 352.6, "endX": 87.5, "endY": 354.9},
    {"cp1X": 84.2, "cp1Y": 386.5, "cp2X": 85.9, "cp2Y": 421.8, "endX": 77.0, "endY": 449.7},
    {"cp1X": 71.7, "cp1Y": 466.0, "cp2X": 65.7, "cp2Y": 482.3, "endX": 57.7, "endY": 494.4},
    {"cp1X": 46.8, "cp1Y": 511.0, "cp2X": 31.4, "cp2Y": 515.7, "endX": 20.0, "endY": 531.4},
    {"cp1X": 18.4, "cp1Y": 533.7, "cp2X": 18.0, "cp2Y": 542.9, "endX": 20.1, "endY": 542.9},
    {"cp1X": 35.7, "cp1Y": 542.9, "cp2X": 49.0, "cp2Y": 519.1, "endX": 60.8, "endY": 500.6},
    {"cp1X": 68.5, "cp1Y": 488.4, "cp2X": 67.9, "cp2Y": 457.1, "endX": 77.9, "endY": 454.9},
    {"cp1X": 84.3, "cp1Y": 453.5, "cp2X": 93.6, "cp2Y": 453.0, "endX": 96.6, "endY": 463.2},
    {"cp1X": 103.0, "cp1Y": 483.6, "cp2X": 97.3, "cp2Y": 510.1, "endX": 99.2, "endY": 533.3},
    {"cp1X": 99.5, "cp1Y": 537.5, "cp2X": 101.1, "cp2Y": 541.8, "endX": 103.2, "endY": 543.5},
    {"cp1X": 108.1, "cp1Y": 547.7, "cp2X": 114.3, "cp2Y": 546.0, "endX": 119.6, "endY": 543.9},
    {"cp1X": 123.8, "cp1Y": 542.1, "cp2X": 127.8, "cp2Y": 537.8, "endX": 130.9, "endY": 532.6},
    {"cp1X": 138.9, "cp1Y": 519.3, "cp2X": 137.1, "cp2Y": 494.7, "endX": 142.2, "endY": 477.4},
    {"cp1X": 144.1, "cp1Y": 470.6, "cp2X": 147.9, "cp2Y": 463.8, "endX": 152.0, "endY": 463.4},
    {"cp1X": 153.8, "cp1Y": 463.4, "cp2X": 154.9, "cp2Y": 467.9, "endX": 154.9, "endY": 471.0},
    {"cp1X": 154.3, "cp1Y": 494.0, "cp2X": 142.2, "cp2Y": 521.2, "endX": 149.8, "endY": 539.7},
    {"cp1X": 152.4, "cp1Y": 546.0, "cp2X": 158.4, "cp2Y": 544.5, "endX": 162.7, "endY": 543.9},
    {"cp1X": 169.0, "cp1Y": 542.9, "cp2X": 175.5, "cp2Y": 540.4, "endX": 181.1, "endY": 535.1},
    {"cp1X": 189.3, "cp1Y": 527.5, "cp2X": 194.7, "cp2Y": 511.0, "endX": 198.1, "endY": 495.6},
    {"cp1X": 207.1, "cp1Y": 455.9, "cp2X": 207.8, "cp2Y": 411.8, "endX": 214.5, "endY": 370.8},
    {"cp1X": 215.6, "cp1Y": 364.0, "cp2X": 217.8, "cp2Y": 355.2, "endX": 221.6, "endY": 354.0},
    {"cp1X": 224.9, "cp1Y": 353.1, "cp2X": 226.0, "cp2Y": 364.6, "endX": 225.6, "endY": 370.4},
    {"cp1X": 222.3, "cp1Y": 426.3, "cp2X": 210.0, "cp2Y": 479.7, "endX": 205.5, "endY": 535.2},
    {"cp1X": 205.1, "cp1Y": 539.7, "cp2X": 207.4, "cp2Y": 545.1, "endX": 209.7, "endY": 546.5},
    {"cp1X": 216.3, "cp1Y": 549.7, "cp2X": 223.8, "cp2Y": 546.8, "endX": 229.8, "endY": 541.4},
    {"cp1X": 237.2, "cp1Y": 534.7, "cp2X": 243.8, "cp2Y": 524.1, "endX": 248.1, "endY": 511.5},
    {"cp1X": 262.4, "cp1Y": 470.1, "cp2X": 261.7, "cp2Y": 417.0, "endX": 270.1, "endY": 370.6},
    {"cp1X": 271.4, "cp1Y": 363.8, "cp2X": 272.8, "cp2Y": 354.9, "endX": 276.7, "endY": 352.6},
    {"cp1X": 278.3, "cp1Y": 351.6, "cp2X": 280.5, "cp2Y": 354.4, "endX": 281.1, "endY": 357.3},
    {"cp1X": 282.0, "cp1Y": 362.5, "cp2X": 281.4, "cp2Y": 368.3, "endX": 281.1, "endY": 373.7},
    {"cp1X": 278.1, "cp1Y": 422.3, "cp2X": 267.1, "cp2Y": 468.4, "endX": 262.7, "endY": 516.5},
    {"cp1X": 261.9, "cp1Y": 525.5, "cp2X": 261.0, "cp2Y": 539.5, "endX": 265.6, "endY": 543.4},
    {"cp1X": 269.1, "cp1Y": 546.3, "cp2X": 273.2, "cp2Y": 547.3, "endX": 276.9, "endY": 546.0},
    {"cp1X": 282.5, "cp1Y": 543.7, "cp2X": 288.3, "cp2Y": 540.1, "endX": 292.8, "endY": 533.7},
    {"cp1X": 305.1, "cp1Y": 516.3, "cp2X": 309.5, "cp2Y": 485.5, "endX": 319.9, "endY": 464.6},
    {"cp1X": 323.5, "cp1Y": 457.1, "cp2X": 328.4, "cp2Y": 449.5, "endX": 333.9, "endY": 449.4},
    {"cp1X": 337.7, "cp1Y": 449.2, "cp2X": 342.3, "cp2Y": 451.3, "endX": 344.7, "endY": 456.6},
    {"cp1X": 348.8, "cp1Y": 466.2, "cp2X": 350.6, "cp2Y": 478.6, "endX": 351.1, "endY": 490.5},
    {"cp1X": 351.5, "cp1Y": 500.4, "cp2X": 350.4, "cp2Y": 510.8, "endX": 348.1, "endY": 520.0},
    {"cp1X": 346.0, "cp1Y": 528.0, "cp2X": 342.6, "cp2Y": 536.1, "endX": 338.2, "endY": 540.1},
    {"cp1X": 334.9, "cp1Y": 543.4, "cp2X": 330.9, "cp2Y": 546.1, "endX": 327.2, "endY": 544.9},
    {"cp1X": 323.4, "cp1Y": 543.7, "cp2X": 319.0, "cp2Y": 539.5, "endX": 317.6, "endY": 533.2},
    {"cp1X": 315.6, "cp1Y": 523.9, "cp2X": 314.8, "cp2Y": 513.6, "endX": 315.8, "endY": 503.9},
    {"cp1X": 316.9, "cp1Y": 492.1, "cp2X": 319.3, "cp2Y": 480.2, "endX": 323.1, "endY": 470.3},
    {"cp1X": 325.7, "cp1Y": 463.8, "cp2X": 329.7, "cp2Y": 458.9, "endX": 333.8, "endY": 456.5},
    {"cp1X": 348.6, "cp1Y": 450.0, "cp2X": 363.2, "cp2Y": 443.8, "endX": 378.0, "endY": 437.6}
  ],
  samplesPerSegment: 15,
  duration: 5.0
)
```

### 4. Verify the result

```tool
get_screen
```

You should see the Apple "hello" drawn in a single flowing cursive stroke
across the Touch Canvas.
