import Foundation

// Small terminal surface for the official CLI's rendered usage panel. Never persisted.
struct ClaudeTerminalScreen {
    let rows:Int,columns:Int
    private var cells:[[Character]]
    private var row=0,column=0
    init(rows:Int=80,columns:Int=160){self.rows=rows;self.columns=columns;cells=Array(repeating:Array(repeating:" ",count:columns),count:rows)}
    private mutating func linefeed(){row += 1;column=0;if row>=rows {cells.removeFirst();cells.append(Array(repeating:" ",count:columns));row=rows-1}}
    mutating func render(_ data:Data) {
        let chars=Array(String(decoding:data,as:UTF8.self).unicodeScalars);var i=0
        while i<chars.count {
            let value=chars[i].value
            if value==27 {
                guard i+1<chars.count else{break}
                if chars[i+1]=="[" {
                    var end=i+2
                    while end<chars.count && !(0x40...0x7e).contains(chars[end].value){end += 1}
                    guard end<chars.count else{break}
                    let raw=String(String.UnicodeScalarView(chars[(i+2)..<end]))
                    let values=raw.replacingOccurrences(of:"?",with:"").split(separator:";",omittingEmptySubsequences:false).map{min(10000,max(0,Int($0) ?? 0))}
                    let first=values.first ?? 0,n=max(1,first)
                    switch chars[end] {
                    case "A":row=max(0,row-n)
                    case "B":row=min(rows-1,row+n)
                    case "C":column=min(columns-1,column+n)
                    case "D":column=max(0,column-n)
                    case "E":row=min(rows-1,row+n);column=0
                    case "F":row=max(0,row-n);column=0
                    case "G":column=min(columns-1,n-1)
                    case "d":row=min(rows-1,n-1)
                    case "H","f":row=min(rows-1,max(1,first)-1);column=min(columns-1,max(1,values.count>1 ? values[1] : 1)-1)
                    case "J":
                        if first==2 || first==3 {cells=Array(repeating:Array(repeating:" ",count:columns),count:rows)}
                        else if first==0 {for c in column..<columns {cells[row][c]=" "};if row+1<rows {for r in (row+1)..<rows {cells[r]=Array(repeating:" ",count:columns)}}}
                    case "K":
                        let range=first==2 ? 0..<columns : first==1 ? 0..<min(columns,column+1) : column..<columns
                        for c in range {cells[row][c]=" "}
                    default:break
                    }
                    i=end+1;continue
                }
                if chars[i+1]=="]" || chars[i+1]=="P" {
                    var end=i+2
                    while end<chars.count {
                        if chars[end].value==7 {end += 1;break}
                        if chars[end].value==27,end+1<chars.count,chars[end+1]=="\\" {end += 2;break}
                        end += 1
                    }
                    i=end;continue
                }
                i += 2;continue
            }
            switch value {
            case 13:column=0
            case 10:linefeed()
            case 8:column=max(0,column-1)
            case 9:column=min(columns-1,((column/8)+1)*8)
            case 32...0x10ffff:
                if column>=columns {linefeed()}
                cells[row][column]=Character(String(chars[i]));column += 1
            default:break
            }
            i += 1
        }
    }
    var text:String {cells.map{String($0).trimmingCharacters(in:.whitespaces)}.joined(separator:"\n")}
}
