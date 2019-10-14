# Project data

This folder contains static data of the project. The files
`data/output_20191622_041444_geocoding_edit.csv` and
`data/output_20191622_041444_geocoding_edit.xlsx`contain identical
information. The files contain (manually) edited geocoding information. Please
use the `.xlsx` to edit the geocoding information. Convert the file to a CSV
with the following lines of Python code.

```python
import pandas as pd

# read the xlsx file
df = pd.read_excel("data/output_20191622_041444_geocoding_edit.xlsx")
# write to csv file
df.to_csv("data/output_20191622_041444_geocoding_edit.csv", index=False)
```
