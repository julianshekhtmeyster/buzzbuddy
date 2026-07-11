import ContactsUI
import SwiftUI

enum PhoneNumberNormalizer {
    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return "" }

        if trimmed.hasPrefix("+") {
            return "+\(digits)"
        }
        if digits.count == 11, digits.hasPrefix("1") {
            return "+\(digits)"
        }
        if digits.count == 10,
           ["US", "CA"].contains(Locale.current.region?.identifier ?? "") {
            return "+1\(digits)"
        }
        return digits
    }

    static func isValid(_ value: String) -> Bool {
        let normalized = normalized(value)
        let digits = normalized.filter(\.isNumber)
        return normalized.hasPrefix("+") && (8...15).contains(digits.count)
    }
}

struct ContactPickerView: UIViewControllerRepresentable {
    var onSelect: (_ name: String, _ phoneNumber: String) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        picker.predicateForSelectionOfProperty = NSPredicate(
            format: "key == %@",
            CNContactPhoneNumbersKey
        )
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerView

        init(parent: ContactPickerView) {
            self.parent = parent
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.onCancel()
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            guard contactProperty.key == CNContactPhoneNumbersKey,
                  let phone = contactProperty.value as? CNPhoneNumber else { return }
            let contact = contactProperty.contact
            let formattedName = CNContactFormatter.string(from: contact, style: .fullName)
                ?? contact.givenName
            parent.onSelect(formattedName, PhoneNumberNormalizer.normalized(phone.stringValue))
        }
    }
}
