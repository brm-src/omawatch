import QtQuick
import qs.Commons
import qs.Ui

BarIconButton {
  id: root

  property string moduleName: "io.github.brm-src.omawatch"
  readonly property bool isSpanish: Qt.locale().name.toLowerCase().startsWith("es")

  slotSize: bar ? bar.barSize : 27
  opticalSize: 16
  fontSize: 12
  text: "\uf008"
  tooltipText: root.isSpanish
    ? "omawatch · qué ver hoy, según tu ánimo"
    : "omawatch · what to watch tonight, by mood"

  onPressed: function(button) {
    if (button === Qt.LeftButton && root.bar)
      root.bar.run("omarchy-shell shell toggle " + root.moduleName + " '{}'")
  }
}
