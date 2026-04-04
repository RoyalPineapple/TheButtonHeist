import SwiftUI

struct ContactsView: View {
    @State private var searchText = ""
    @State private var selectedDepartment: Department = .all

    enum Department: String, CaseIterable, Identifiable {
        case all = "All"
        case engineering = "Engineering"
        case design = "Design"
        case marketing = "Marketing"
        case operations = "Operations"

        var id: String { rawValue }
    }

    private let contacts: [Contact] = Contact.directory

    private var filteredContacts: [Contact] {
        contacts.filter { contact in
            let matchesDepartment = selectedDepartment == .all
                || contact.department.rawValue == selectedDepartment.rawValue
            let matchesSearch = searchText.isEmpty
                || contact.name.localizedCaseInsensitiveContains(searchText)
                || contact.role.localizedCaseInsensitiveContains(searchText)
            return matchesDepartment && matchesSearch
        }
    }

    private var groupedContacts: [(department: Contact.Department, contacts: [Contact])] {
        let grouped = Dictionary(grouping: filteredContacts, by: \.department)
        return Contact.Department.allCases.compactMap { dept in
            guard let members = grouped[dept], !members.isEmpty else { return nil }
            return (department: dept, contacts: members)
        }
    }

    var body: some View {
        Group {
            if filteredContacts.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(groupedContacts, id: \.department) { group in
                        Section {
                            ForEach(group.contacts) { contact in
                                ContactRow(contact: contact)
                            }
                        } header: {
                            Text(group.department.rawValue)
                        }
                    }
                    Section {
                        Text("Showing \(filteredContacts.count) of \(contacts.count) contacts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search contacts...")
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Department", selection: $selectedDepartment) {
                    ForEach(Department.allCases) { dept in
                        Text(dept.rawValue).tag(dept)
                    }
                }
            }
        }
        .onChange(of: filteredContacts.count) { _, newCount in
            NSLog("[Contacts] filtered results changed (showing: %d, total: %d)", newCount, contacts.count)
        }
    }
}

// MARK: - Subviews

private struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(contact.avatarColor.gradient)
                    .frame(width: 40, height: 40)
                Text(contact.initials)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.headline)
                Text(contact.role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Model

private struct Contact: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let department: Department
    let avatarColor: Color

    var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? (parts.last?.prefix(1) ?? "") : ""
        return "\(first)\(last)"
    }

    enum Department: String, CaseIterable {
        case engineering = "Engineering"
        case design = "Design"
        case marketing = "Marketing"
        case operations = "Operations"
    }

    static let directory: [Contact] = [
        Contact(name: "Alice Chen", role: "Senior Engineer", department: .engineering, avatarColor: .blue),
        Contact(name: "Bob Martinez", role: "Staff Engineer", department: .engineering, avatarColor: .indigo),
        Contact(name: "Clara Zhang", role: "iOS Developer", department: .engineering, avatarColor: .cyan),
        Contact(name: "David Kim", role: "Backend Engineer", department: .engineering, avatarColor: .teal),
        Contact(name: "Elena Volkov", role: "Platform Engineer", department: .engineering, avatarColor: .blue),
        Contact(name: "Felix Okafor", role: "DevOps Engineer", department: .engineering, avatarColor: .indigo),
        Contact(name: "Grace Liu", role: "ML Engineer", department: .engineering, avatarColor: .cyan),
        Contact(name: "Hannah Park", role: "Product Designer", department: .design, avatarColor: .purple),
        Contact(name: "Isaac Tanaka", role: "UX Researcher", department: .design, avatarColor: .pink),
        Contact(name: "Julia Santos", role: "Visual Designer", department: .design, avatarColor: .purple),
        Contact(name: "Kevin Osei", role: "Design Systems Lead", department: .design, avatarColor: .pink),
        Contact(name: "Lena Müller", role: "Interaction Designer", department: .design, avatarColor: .purple),
        Contact(name: "Marco Rossi", role: "Brand Designer", department: .design, avatarColor: .pink),
        Contact(name: "Nadia Petrov", role: "Marketing Lead", department: .marketing, avatarColor: .orange),
        Contact(name: "Omar Hassan", role: "Content Strategist", department: .marketing, avatarColor: .red),
        Contact(name: "Priya Sharma", role: "Growth Manager", department: .marketing, avatarColor: .orange),
        Contact(name: "Quinn Williams", role: "Social Media Lead", department: .marketing, avatarColor: .red),
        Contact(name: "Rachel Dubois", role: "Product Marketing", department: .marketing, avatarColor: .orange),
        Contact(name: "Sam Nakamura", role: "SEO Specialist", department: .marketing, avatarColor: .red),
        Contact(name: "Tanya Ivanova", role: "Operations Manager", department: .operations, avatarColor: .green),
        Contact(name: "Umar Ali", role: "Program Manager", department: .operations, avatarColor: .mint),
        Contact(name: "Vera Johansson", role: "People Ops Lead", department: .operations, avatarColor: .green),
        Contact(name: "Wesley Huang", role: "Finance Analyst", department: .operations, avatarColor: .mint),
        Contact(name: "Xena Papadopoulos", role: "Legal Counsel", department: .operations, avatarColor: .green),
        Contact(name: "Yuki Watanabe", role: "Office Manager", department: .operations, avatarColor: .mint),
    ]
}

#Preview {
    NavigationStack {
        ContactsView()
    }
    .environment(AppSettings())
}
