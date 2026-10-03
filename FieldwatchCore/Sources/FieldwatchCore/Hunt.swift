import Foundation

public enum HuntCue: String, Sendable { case stronger, weaker, stable, noSignal }
public enum Hunt {
    public static func cue(previous: Int?, current: Int?) -> HuntCue { guard let p=previous, let c=current else{return .noSignal}; if c-p >= 4{return .stronger}; if c-p <= -4{return .weaker}; return .stable }
    public static func delta(previous: Int?, current: Int?) -> Int? { guard let p=previous, let c=current else{return nil}; return c-p }
}
