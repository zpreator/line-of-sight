# line-of-sight
An iOS app for discovering line of sight locations to celestial objects and landmarks

## Elevation Data Sources

This app uses **Mapzen DEM (Digital Elevation Model) tiles** for terrain calculations. This data may differ from the 3D terrain displayed in Apple Maps because:

### Why The Difference?

1. **Apple Maps 3D Terrain**: Stylized for visual appeal, may be exaggerated or smoothed
2. **Mapzen DEM Data**: Scientific elevation datasets (SRTM, NED) used for calculations
3. **Resolution**: Zoom 14 tiles (~10m per pixel) with bilinear interpolation
4. **Purpose**: Calculation accuracy vs. visual representation

### What This Means for Users

- **The elevation shown in the app is used for all calculations**
- DEM data represents actual ground elevation for ray-terrain intersections
- Discrepancies of ±10-50m are normal between visual and calculation datasets
- For photography planning, calculation accuracy matters more than visual consistency

### Data Pipeline

```
User Tap → Coordinate → Mapzen DEM Tile → Elevation Query → Ray Marching → Intersection Point
```

All terrain-based calculations (ray marching, intersections, line-of-sight) use this DEM data consistently.

