import AppKit
import ApplicationServices
import Foundation

enum AXQueryError: Error {
    case appNotRunning(String)
    case unsupportedCommand(String)
    case elementNotFound(String)
    case unavailableAttribute(String)
    case actionFailed(String)
}

func attributeValue(_ element: AXUIElement, attribute: String) -> AnyObject? {
    var result: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
    guard error == .success else {
        return nil
    }
    return result
}

func findElement(identifier: String, in root: AXUIElement) -> AXUIElement? {
    if let currentIdentifier = attributeValue(root, attribute: "AXIdentifier") as? String, currentIdentifier == identifier {
        return root
    }

    guard let children = attributeValue(root, attribute: kAXChildrenAttribute as String) as? [AXUIElement] else {
        return nil
    }

    for child in children {
        if let found = findElement(identifier: identifier, in: child) {
            return found
        }
    }

    return nil
}

func point(from value: AnyObject?) -> CGPoint? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else {
        return nil
    }

    var point = CGPoint.zero
    return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
}

func size(from value: AnyObject?) -> CGSize? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else {
        return nil
    }

    var size = CGSize.zero
    return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
}

func stringValue(from value: AnyObject?) -> String? {
    if let string = value as? String {
        return string
    }

    if let number = value as? NSNumber {
        return number.stringValue
    }

    return nil
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    fatalError("usage: ax-query.swift value|center|press <app-name> <identifier>")
}

let command = arguments[1]
let appName = arguments[2]
let identifier = arguments[3]

guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName == appName || $0.bundleIdentifier == appName
}) else {
    throw AXQueryError.appNotRunning(appName)
}

let root = AXUIElementCreateApplication(app.processIdentifier)
guard let element = findElement(identifier: identifier, in: root) else {
    throw AXQueryError.elementNotFound(identifier)
}

switch command {
case "value":
    if let value = stringValue(from: attributeValue(element, attribute: kAXValueAttribute as String)) {
        print(value)
    } else if let title = stringValue(from: attributeValue(element, attribute: kAXTitleAttribute as String)) {
        print(title)
    } else if let description = stringValue(from: attributeValue(element, attribute: kAXDescriptionAttribute as String)) {
        print(description)
    } else {
        throw AXQueryError.unavailableAttribute(identifier)
    }
case "center":
    guard
        let position = point(from: attributeValue(element, attribute: kAXPositionAttribute as String)),
        let size = size(from: attributeValue(element, attribute: kAXSizeAttribute as String))
    else {
        throw AXQueryError.unavailableAttribute(identifier)
    }

    let x = Int(position.x + (size.width / 2))
    let y = Int(position.y + (size.height / 2))
    print("\(x) \(y)")
case "press":
    let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard error == .success else {
        throw AXQueryError.actionFailed(identifier)
    }
default:
    throw AXQueryError.unsupportedCommand(command)
}
