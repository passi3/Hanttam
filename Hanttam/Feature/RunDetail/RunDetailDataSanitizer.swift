//
//  RunDetailDataSanitizer.swift
//  Hanttam
//

func sanitizedRunDetailData(_ data: RunDetailViewModel.DetailData) -> RunDetailViewModel.DetailData {
    var s = data
    s.altPoints = data.altPoints.filter { $0.altitude.isFinite && $0.latitude.isFinite && $0.longitude.isFinite }
    s.splits = data.splits.map { split in
        var r = split
        if let v = r.elevationChange,   !v.isFinite { r.elevationChange = nil }
        if let v = r.avgHeartRate,      !v.isFinite { r.avgHeartRate = nil }
        if let v = r.avgCadence,        !v.isFinite { r.avgCadence = nil }
        if let v = r.avgStrideLength,   !v.isFinite { r.avgStrideLength = nil }
        if let v = r.avgVerticalOscillation, !v.isFinite { r.avgVerticalOscillation = nil }
        if let v = r.avgPower,          !v.isFinite { r.avgPower = nil }
        if let v = r.avgSpeed,          !v.isFinite { r.avgSpeed = nil }
        if let v = r.avgGroundContactTime, !v.isFinite { r.avgGroundContactTime = nil }
        return r
    }
    s.lapRows = data.lapRows.map { row in
        var r = row
        if let v = r.avgHeartRate,    !v.isFinite { r.avgHeartRate = nil }
        if let v = r.elevationChange, !v.isFinite { r.elevationChange = nil }
        return r
    }
    return s
}
