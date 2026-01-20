// StatusBarController.swift

import Cocoa

class UsageMenuItemView: NSView {
    func showError() {
        let errorImage = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error icon")
        let textAttachment = NSTextAttachment(image: errorImage!)
        let attributedString = NSMutableAttributedString(attachment: textAttachment)
        percentLabel.attributedStringValue = attributedString
    }
}

class StatusBarController {
    func setupMenu() {
        historyMenuItem.title = "Usage History"
        historyMenuItem.image = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: "Usage History Chart")
    }

    func updateHistorySubmenu() {
        let noDataImage = NSImage(systemSymbolName: "tray", accessibilityDescription: "No Data Tray")
        menuItemNoData.title = "No data"
        menuItemNoData.image = noDataImage

        let eomImage = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "Predicted EOM Trend Chart")
        menuItemEOM.title = "Predicted EOM..."
        menuItemEOM.image = eomImage
        menuItemEOM.attributedTitle = NSAttributedString(string: "Predicted EOM...", attributes: [NSAttributedString.Keyattachment: eomImage])

        let addonImage = NSImage(systemSymbolName: "banknote", accessibilityDescription: "Predicted Add-on Banknote")
        menuItemAddon.title = "Predicted Add-on..."
        menuItemAddon.image = addonImage
        menuItemAddon.attributedTitle = NSAttributedString(string: "Predicted Add-on...", attributes: [NSAttributedString.Keyattachment: addonImage])

        let lowAccuracyImage = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Low Prediction Accuracy Warning")
        menuItemLowAccuracy.title = "Low prediction accuracy"
        menuItemLowAccuracy.image = lowAccuracyImage

        let mediumAccuracyImage = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: "Medium Prediction Accuracy Chart")
        menuItemMediumAccuracy.title = "Medium prediction accuracy"
        menuItemMediumAccuracy.image = mediumAccuracyImage

        let staleDataImage = NSImage(systemSymbolName: "clock", accessibilityDescription: "Data Stale Clock")
        menuItemStaleData.title = "Data is stale"
        menuItemStaleData.image = staleDataImage

        let predictionPeriodImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Prediction Period Gear")
        menuItemPredictionPeriod.title = "Prediction Period"
        menuItemPredictionPeriod.image = predictionPeriodImage
    }
}