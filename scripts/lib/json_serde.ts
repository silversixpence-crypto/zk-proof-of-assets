// https://blog.stackademic.com/json-parse-and-stringify-bigint-objects-and-uint8arrays-e861a7b327c8

const JSON_KEY_BIGINT = "__bigint__";
const JSON_KEY_UINT8ARRAY = "__uint8array__";

// An inlined utilise to check for null and undefined
export const nonNullish = <T>(
  argument: T | undefined | null,
): argument is NonNullable<T> => argument !== null && argument !== undefined;

// The parser that interprets revived BigInt and Uint8Array when constructing JavaScript values or objects.
export const jsonReplacer = (_key: string, value: unknown): unknown => {
  if (typeof value === "bigint") {
    return { [JSON_KEY_BIGINT]: `${value}` };
  }

  if (nonNullish(value) && value instanceof Uint8Array) {
    return { [JSON_KEY_UINT8ARRAY]: Array.from(value) };
  }

  return value;
};

// A function that alters the behavior of the stringification process for BigInt and Uint8Array.
export const jsonReviver = (_key: string, value: unknown): unknown => {
  const mapValue = <T>(key: string): T => (value as Record<string, T>)[key];

  if (
    nonNullish(value) &&
    typeof value === "object" &&
    JSON_KEY_BIGINT in value
  ) {
    return BigInt(mapValue(JSON_KEY_BIGINT));
  }

  if (
    nonNullish(value) &&
    typeof value === "object" &&
    JSON_KEY_UINT8ARRAY in value
  ) {
    return Uint8Array.from(mapValue(JSON_KEY_UINT8ARRAY));
  }

  return value;
};
