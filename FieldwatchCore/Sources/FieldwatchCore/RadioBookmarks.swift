import Foundation

public enum RadioBookmarks {
    public static func add(_ key:String, to keys:Set<String>)->Set<String>{ var x=keys;x.insert(key);return x }
    public static func remove(_ key:String, from keys:Set<String>)->Set<String>{ var x=keys;x.remove(key);return x }
    public static func toggle(_ key:String, in keys:Set<String>)->Set<String>{ keys.contains(key) ? remove(key,from:keys) : add(key,to:keys) }
    public static func contains(_ key:String, in keys:Set<String>)->Bool { keys.contains(key) }
}
