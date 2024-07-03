"""
Used to get the plane of best fit for the benchmark data.

Example:
- (number of signatures, merkle tree height) VS non-linear constraints for layer 2 circuit
"""

import numpy as np
from sklearn.linear_model import LinearRegression

def find_best_fit_plane(data):
  """
  This function takes a list of (x, y, z) coordinates and finds the equation
  of the plane of best fit.

  Args:
      data: A list of tuples containing (x, y, z) coordinates.

  Returns:
      A tuple containing a, b, c, and d representing the plane equation:
          ax + by + cz + d = 0
  """
  # Convert data to numpy arrays
  X = np.array([[point[0], point[1]] for point in data])
  y = np.array([point[2] for point in data])

  # Use linear regression to find plane coefficients
  model = LinearRegression()
  model.fit(X, y)

  # Extract coefficients (a, b, and c) and offset (d)
  a = model.coef_[0]
  b = model.coef_[1]
  c = -1  # Plane equation has z coefficient as -1 for linear regression
  d = model.intercept_

  return a, b, c, d

# layer 2 non-linear constraints (number of signatures, merkle tree height, constraints)
data = [(4, 12, 19981480), (1, 5, 19823616), (2, 25, 19987876), (7, 25, 20784765), (16, 25, 22219209), (128, 25, 40070665)]
a, b, c, d = find_best_fit_plane(data)

# Print the equation of the plane of best fit
print(f"Plane equation: {a:.2f}x + {b:.2f}y + {c:.2f}z + {d:.2f} = 0")
