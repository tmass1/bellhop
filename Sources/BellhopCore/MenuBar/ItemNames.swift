/// Autosave names for Bellhop's own status items.
///
/// macOS 27's menu bar agent keeps its own record of an installed app's items, keyed by name, and once it has one it
/// ignores the position the app stores. A record saved while the bar was in a bad state stays wrong: on Oct 27
/// Bellhop's icon had been recorded while pushed far left, so every divider (still placed from the stored 250)
/// landed right of the icon, tucked nothing and pushed the icon left again. A new generation renames every item;
/// the agent has no record for the new names and places them from Bellhop's numbers again.
public enum ItemNames {
    public static func icon(generation: Int) -> String {
        "Bellhop" + suffix(generation)
    }

    public static func divider(index: Int, generation: Int) -> String {
        let base = "BellhopDivider" + suffix(generation)
        return index == 0 ? base : "\(base) \(index + 1)"
    }

    public static func keeper(_ id: String, generation: Int) -> String {
        "BellhopKeeper" + suffix(generation) + " " + id.replacingOccurrences(of: "#", with: " ")
    }

    /// Generation 0 keeps the names installs already have.
    private static func suffix(_ generation: Int) -> String {
        generation == 0 ? "" : " g\(generation)"
    }
}
