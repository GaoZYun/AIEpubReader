import SwiftUI

/// 极简风格的书籍封面组件
struct BookCoverView: View {
    let title: String
    let author: String
    let fileType: String
    let coverImage: NSImage?
    var themeColor: Color? = nil
    
    @State private var isHovering: Bool = false
    
    // 生成随机渐变色背景（基于标题哈希）
    private var gradientColors: [Color] {
        if let themeColor = themeColor {
            return [themeColor.opacity(0.8), themeColor.opacity(0.4)]
        }
        let hash = abs(title.hashValue)
        let colors: [[Color]] = [
            [Color(hex: "EEF2FF"), Color(hex: "C7D2FE")], // Indigo
            [Color(hex: "F0F9FF"), Color(hex: "BAE6FD")], // Sky
            [Color(hex: "ECFDF5"), Color(hex: "A7F3D0")], // Emerald
            [Color(hex: "FFFBEB"), Color(hex: "FDE68A")], // Amber
            [Color(hex: "FEF2F2"), Color(hex: "FECACA")], // Red
            [Color(hex: "FAF5FF"), Color(hex: "E9D5FF")], // Purple
            [Color(hex: "FDF4FF"), Color(hex: "FBCFE8")], // Pink
            [Color(hex: "F4F4F5"), Color(hex: "D4D4D8")], // Zinc
        ]
        return colors[hash % colors.count]
    }
    
    var body: some View {
        ZStack {
            // 背景层
            if let cover = coverImage {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 140, height: 200)
                    .clipped()
            } else {
                // 极简占位封面
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        
                        Text(title)
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundColor(.black.opacity(0.8))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        
                        Text(author.isEmpty ? "Unknown" : author)
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundColor(.black.opacity(0.5))
                            .lineLimit(1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
                
                // 文件类型角标
                VStack {
                    HStack {
                        Spacer()
                        Text(fileType.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.black.opacity(0.4))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.5))
                            .cornerRadius(4)
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: 140, height: 200)
        .background(Color.white)
        .cornerRadius(12)
        // 阴影效果
        .shadow(
            color: Color.black.opacity(isHovering ? 0.15 : 0.08),
            radius: isHovering ? 16 : 8,
            x: 0,
            y: isHovering ? 8 : 4
        )
        // 悬停缩放效果
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        // 边框（极细，仅用于深色模式适配）
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        BookCoverView(title: "The Great Gatsby", author: "F. Scott Fitzgerald", fileType: "EPUB", coverImage: nil)
        BookCoverView(title: "Swift Programming", author: "Apple Inc.", fileType: "PDF", coverImage: nil)
    }
    .padding(40)
    .background(Color(nsColor: .windowBackgroundColor))
}
