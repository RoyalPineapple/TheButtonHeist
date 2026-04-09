import SwiftUI

struct CustomContentDemo: View {
    var body: some View {
        List {
            Section("File Info") {
                FileInfoRow(
                    name: "Quarterly Report.pdf",
                    fileType: "PDF Document",
                    size: "2.4 MB",
                    modified: "March 15, 2026",
                    author: "Jordan Lee"
                )
                FileInfoRow(
                    name: "Team Photo.heic",
                    fileType: "HEIC Image",
                    size: "8.1 MB",
                    modified: "April 2, 2026",
                    author: "Sam Rivera"
                )
                FileInfoRow(
                    name: "Budget Draft.xlsx",
                    fileType: "Spreadsheet",
                    size: "340 KB",
                    modified: "April 8, 2026",
                    author: "Alex Chen"
                )
            }

            Section("Product Cards") {
                ProductInfoCard(
                    name: "Wireless Headphones",
                    price: "$79.99",
                    rating: "4.5 out of 5",
                    reviews: "1,247 reviews",
                    color: "Midnight Black",
                    availability: "In Stock"
                )
                ProductInfoCard(
                    name: "USB-C Hub",
                    price: "$34.99",
                    rating: "4.2 out of 5",
                    reviews: "863 reviews",
                    color: "Space Gray",
                    availability: "Ships in 2-3 days"
                )
            }

            Section("Weather Conditions") {
                WeatherInfoRow(
                    city: "Portland",
                    temperature: "58°F",
                    condition: "Overcast",
                    humidity: "82%",
                    wind: "12 mph NW",
                    uvIndex: "Low"
                )
                WeatherInfoRow(
                    city: "Phoenix",
                    temperature: "97°F",
                    condition: "Clear",
                    humidity: "15%",
                    wind: "5 mph S",
                    uvIndex: "Very High"
                )
            }
        }
        .navigationTitle("Custom Content")
    }
}

// MARK: - File Info Row

private struct FileInfoRow: View {
    let name: String
    let fileType: String
    let size: String
    let modified: String
    let author: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text(fileType)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityCustomContent(Text("File Type"), Text(fileType), importance: .high)
        .accessibilityCustomContent(Text("Size"), Text(size))
        .accessibilityCustomContent(Text("Modified"), Text(modified))
        .accessibilityCustomContent(Text("Author"), Text(author))
    }
}

// MARK: - Product Info Card

private struct ProductInfoCard: View {
    let name: String
    let price: String
    let rating: String
    let reviews: String
    let color: String
    let availability: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.headline)
            Text(price)
                .font(.title3)
                .fontWeight(.semibold)
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text(rating)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityCustomContent(Text("Price"), Text(price), importance: .high)
        .accessibilityCustomContent(Text("Rating"), Text(rating))
        .accessibilityCustomContent(Text("Reviews"), Text(reviews))
        .accessibilityCustomContent(Text("Color"), Text(color))
        .accessibilityCustomContent(Text("Availability"), Text(availability))
    }
}

// MARK: - Weather Info Row

private struct WeatherInfoRow: View {
    let city: String
    let temperature: String
    let condition: String
    let humidity: String
    let wind: String
    let uvIndex: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(city)
                    .font(.headline)
                Text(condition)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(temperature)
                .font(.title2)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
        .accessibilityCustomContent(Text("Temperature"), Text(temperature), importance: .high)
        .accessibilityCustomContent(Text("Condition"), Text(condition))
        .accessibilityCustomContent(Text("Humidity"), Text(humidity))
        .accessibilityCustomContent(Text("Wind"), Text(wind))
        .accessibilityCustomContent(Text("UV Index"), Text(uvIndex))
    }
}
