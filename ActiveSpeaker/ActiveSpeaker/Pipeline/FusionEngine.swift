import Foundation

/// Combines audio and video processor outputs into a single SpeakerState.
///
/// Pure value type with no side effects — easy to unit test and swap.
struct FusionEngine {
    var audioThreshold: Float = 0.5
    var mouthVarianceThreshold: Float = 0.00001

    func fuse(audioProb: Float, mouthVariance: Float) -> SpeakerState {
        let audioActive = audioProb > audioThreshold
        let mouthActive = mouthVariance > mouthVarianceThreshold

        switch (audioActive, mouthActive) {
        case (true, true):   return .speaking
        case (true, false),
             (false, true):  return .maybe
        case (false, false): return .silent
        }
    }
}
