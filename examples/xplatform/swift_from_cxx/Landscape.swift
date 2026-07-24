public struct MountainPeak {
  let name: String
  let height: Float

  public init(name: String, height: Float) {
    self.name = name
    self.height = height
  }

  public func printDescription() {
    print("Peak: \(name), height: \(height)")
  }
}

public class MountainRange {
  let peaks: [MountainPeak]

  public init(peaks: [MountainPeak]) {
    self.peaks = peaks
  }

  public func printPeaks() {
    print("Peaks in range:")
    for peak in peaks {
      peak.printDescription()
    }
  }
}

// Simple enum.
public enum VolcanoStatus {
  case dormant
  case active
}

// enum with associated values.
public enum LandmarkIdentifier {
  case name(String)
  case id(Int)
}
