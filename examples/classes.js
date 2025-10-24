#!/usr/bin/env node
/**
 * JavaScript Classes and Object-Oriented Programming Example
 * Demonstrates classes, inheritance, and methods
 */

// Simple class
class Point {
  constructor(x, y) {
    this.x = x;
    this.y = y;
  }

  distanceFromOrigin() {
    return Math.sqrt(this.x ** 2 + this.y ** 2);
  }

  toString() {
    return `Point(${this.x}, ${this.y})`;
  }
}

// Class with inheritance
class Shape {
  constructor(name) {
    this.name = name;
  }

  describe() {
    return `This is a ${this.name}`;
  }
}

class Rectangle extends Shape {
  constructor(width, height) {
    super("rectangle");
    this.width = width;
    this.height = height;
  }

  area() {
    return this.width * this.height;
  }

  perimeter() {
    return 2 * (this.width + this.height);
  }

  toJSON() {
    return {
      name: this.name,
      width: this.width,
      height: this.height,
      area: this.area(),
      perimeter: this.perimeter()
    };
  }
}

// Main execution
function main() {
  // Test Point
  const p1 = new Point(3, 4);
  console.log(`Point: ${p1}`);
  console.log(`Distance from origin: ${p1.distanceFromOrigin().toFixed(2)}`);

  // Test Rectangle
  const rect = new Rectangle(10, 5);
  console.log(`\n${rect.describe()}`);
  console.log(`Width: ${rect.width}, Height: ${rect.height}`);
  console.log(`Area: ${rect.area()}`);
  console.log(`Perimeter: ${rect.perimeter()}`);

  console.log(`\nRectangle as JSON:`);
  console.log(JSON.stringify(rect.toJSON(), null, 2));

  // Array of points
  const points = Array.from({ length: 3 }, (_, i) => new Point(i + 1, (i + 1) * 2));
  console.log(`\nPoints: [${points.join(", ")}]`);
  console.log(`Distances: [${points.map(p => p.distanceFromOrigin().toFixed(2)).join(", ")}]`);
}

main();
