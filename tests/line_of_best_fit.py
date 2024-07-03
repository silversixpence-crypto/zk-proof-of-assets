"""
Used to get the line of best fit for the benchmark data.

Example:
- number of signatures VS non-linear constraints for layer 1 circuit
"""

import numpy as np

def find_best_fit_line(data):
  """
  This function takes a list of (x, y) coordinates and returns the slope and intercept
  of the line of best fit.

  Args:
      data: A list of tuples containing (x, y) coordinates.

  Returns:
      A tuple containing the slope and intercept of the best fit line.
  """
  # Extract x and y coordinates from data list
  x, y = zip(*data)
  x = np.array(x)
  y = np.array(y)

  # Use polyfit to find coefficients
  slope, intercept = np.polyfit(x, y, 1)

  return slope, intercept

# layer 1 non-linear constraints (number of signatures, constraints)
data = [(1, 1509221), (2, 1932908), (2, 1932908), (4, 1932908), (7, 4161827), (16, 8173925), (128, 58102853)]
slope, intercept = find_best_fit_line(data)

# Print the equation of the best fit line (y = mx + b)
print(f"Equation of best fit line: y = {slope:.2f}x + {intercept:.2f}")
