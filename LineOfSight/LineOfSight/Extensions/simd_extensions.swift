//
//  simd_extensions.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/21/25.
//

import simd

extension simd_double3 {
    var normalized: simd_double3 {
        return simd.normalize(self)
    }
}
