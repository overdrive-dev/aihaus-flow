export function increment(value) {
  if (!Number.isFinite(value)) {
    throw new TypeError("value must be a finite number");
  }
  return value + 1;
}
