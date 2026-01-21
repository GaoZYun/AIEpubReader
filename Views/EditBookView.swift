import SwiftUI
import SwiftData

struct EditBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var book: BookItem
    
    @State private var title: String
    @State private var author: String
    @State private var selectedColor: Color
    
    init(book: BookItem) {
        self.book = book
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author ?? "")
        
        if let hex = book.themeColor {
            _selectedColor = State(initialValue: Color(hex: hex))
        } else {
            _selectedColor = State(initialValue: Color.blue)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("编辑书籍信息")
                .font(.headline)
                .padding(.top)
            
            Form {
                TextField("书名", text: $title)
                TextField("作者", text: $author)
                
                ColorPicker("显示颜色", selection: $selectedColor)
            }
            .formStyle(.grouped)
            
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    book.title = title
                    book.author = author.isEmpty ? nil : author
                    book.themeColor = selectedColor.toHex()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }
}

extension Color {
    func toHex() -> String? {
        guard let components = cgColor?.components, components.count >= 3 else {
            return nil
        }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != 1.0 {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}
