#!/usr/bin/env python3
"""
Python Classes and Object-Oriented Programming Example
Demonstrates classes, inheritance, and methods
"""

from dataclasses import dataclass
from typing import List

# Using dataclass for simpler class definition
@dataclass
class Point:
    x: float
    y: float

    def distance_from_origin(self):
        return (self.x ** 2 + self.y ** 2) ** 0.5

    def __str__(self):
        return f"Point({self.x}, {self.y})"


# Traditional class with inheritance
class Shape:
    def __init__(self, name):
        self.name = name

    def describe(self):
        return f"This is a {self.name}"


class Rectangle(Shape):
    def __init__(self, width, height):
        super().__init__("rectangle")
        self.width = width
        self.height = height

    def area(self):
        return self.width * self.height

    def perimeter(self):
        return 2 * (self.width + self.height)


# Main execution
if __name__ == "__main__":
    # Test Point
    p1 = Point(3, 4)
    print(f"Point: {p1}")
    print(f"Distance from origin: {p1.distance_from_origin():.2f}")

    # Test Rectangle
    rect = Rectangle(10, 5)
    print(f"\n{rect.describe()}")
    print(f"Width: {rect.width}, Height: {rect.height}")
    print(f"Area: {rect.area()}")
    print(f"Perimeter: {rect.perimeter()}")

    # List comprehension with objects
    points = [Point(i, i*2) for i in range(1, 4)]
    print(f"\nPoints: {[str(p) for p in points]}")
    print(f"Distances: {[p.distance_from_origin() for p in points]}")
