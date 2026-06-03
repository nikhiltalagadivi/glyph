import sys

def create_file(name, parts, lines, imports):
    with open(f"Sources/TabNote/{name}", "w") as f:
        f.write(imports)
        for (start, end) in parts:
            f.writelines(lines[start:end])

def main():
    with open("Sources/TabNote/main.swift", "r") as f:
        lines = f.readlines()
        
    imports = "".join(lines[0:11]) + "\n"
    
    # Parts are tuples of (start_index, end_index) where index is line_number - 1
    create_file("Extensions.swift", [(11, 18), (2100, len(lines))], lines, imports)
    create_file("TabNoteApp.swift", [(18, 35)], lines, imports)
    create_file("EditorScreen.swift", [(35, 73)], lines, imports)
    create_file("UIComponents.swift", [(73, 142)], lines, imports)
    create_file("EditorViewModel.swift", [(142, 445)], lines, imports)
    create_file("RichTextEditor.swift", [(445, 645)], lines, imports)
    create_file("TabNoteTextView.swift", [(645, 1205)], lines, imports) # includes GlassStatusLabel
    create_file("MathTranslation.swift", [(1205, 1227), (1270, 1512)], lines, imports)
    create_file("LatexEditPopoverView.swift", [(1227, 1270)], lines, imports)
    create_file("OllamaClient.swift", [(1512, 2100)], lines, imports)

if __name__ == "__main__":
    main()
