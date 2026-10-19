#!/usr/bin/env python3
"""WCAG contrast checks for the app's opaque text/surface pairs; no dependencies."""
def luminance(color):
    components = [int(color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in components]
    return sum(a * b for a, b in zip(linear, (0.2126, 0.7152, 0.0722)))

def ratio(a, b):
    high, low = sorted([luminance(a), luminance(b)], reverse=True)
    return (high + 0.05) / (low + 0.05)

pairs = [("Primary button", "FFFFFF", "1D4ED8"), ("Primary hover", "FFFFFF", "1E40AF")]
for name, texts, surfaces in [
    ("Light", ["111827", "4B5563", "1D4ED8", "047857", "92400E", "B91C1C"], ["FFFFFF", "F3F4F6", "E8F0FF"]),
    ("Dark", ["F3F4F6", "B9C3D1", "93B4FF", "6EE7B7", "FCD34D", "FCA5A5"], ["111827", "1F2937", "243B62"]),
]:
    pairs.extend((name, text, surface) for text in texts for surface in surfaces)
for label, text, surface in pairs:
    value = ratio(text, surface)
    assert value >= 4.5, f"{label}: #{text} on #{surface} is only {value:.2f}:1"
print(f"Passed {len(pairs)} text/surface pairs (minimum {min(ratio(t, s) for _, t, s in pairs):.2f}:1).")
