#!/usr/bin/env node
function parse(s) {
  if (!s) return [];
  try {
    return JSON.parse(s);
  } catch (e) {
    return [];
  }
}
