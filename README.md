
<!-- README.md is generated from README.Rmd. Please edit that file -->

# kidneyoutcomes: Kidney Outcomes Analysis for Transplantation

<!-- badges: start -->
<!-- badges: end -->

The goal of **kidneyoutcomes** is to processes serum creatinine data to
identify Acute Kidney Injury (AKI) events and progression to Chronic
Kidney Disease (CKD) stages within a defined baseline context. This
package was developed for use in islet transplantation but may be
adaptable to other transplant settings where measurement of serum
creatinine is frequent. Read on for a summary of the implementation of
the logic that was used to define AKI and CKD in this setting.

## Installation

You can install the development version of kidneyoutcomes from
[GitHub](https://github.com/) with:

``` r
# Install devtools if not already installed
install.packages("devtools")

# Install kidneyoutcomes
devtools::install_github("yourusername/kidneyoutcomes")
```

## Example

This is a basic example of the package useage :

``` r
library(kidneyoutcomes)
library(rio)

#load in your appropriately formatted file containing: patient id, date of transplant (or baseline),date of laboratory result, age at laboratory result, sex and creatinine (mg/dl)  
inputdataframe<-rio::import("path/to/input.csv")

# Run the function
kidneyoutcomes::kidneyoutcomesintx(
  inputdataframe = inputdataframe,
  outputdirectory = "path/to/output",
  datecollocation = 3
)
```

### How to format your input file

Please format your input file that you will load into R to run the
function over as below. Please retain names of columns and pay attention
to units. The definitions of each of these variables are alos found
below.

## Identification of AKI and CKD in the Islet transplanation context

This function calculates the CKD-EPI 2021 derived eGFR per individual
from the serum creatinine, age at lab, and sex.

### 1.Identification of CKD Episodes

- Episodes of CKD are first identified based on the [KDIGO
  criteria](https://www.sciencedirect.com/science/article/pii/S0085253823007664?via%3Dihub)
  as sustained eGFR below threshold for at least **90 days**.

### 2.Definition of AKI

- AKI is defined based on the [KDIGO
  criteria](https://www.sciencedirect.com/science/article/pii/S0085253823007664?via%3Dihub)
  and implemented using the logic of the algorithm applied in the [UK
  National Health Service
  (NHS)](https://www.england.nhs.uk/wp-content/uploads/2014/06/psa-aki-alg.pdf).
  The reference value depended on the number of days since a previous
  result:

  - Creatinine result ≥1.5 times higher than the **median** of all
    previous creatinine measures in the previous 8–365 days.  
  - Creatinine result ≥1.5 times higher than the **lowest creatinine**
    from the previous 7 days.  
  - Creatinine \>26 mmol/L higher than the **lowest creatinine** from
    the previous 48 hours.

- Creatinine results in the first 7 days post-transplant were assessed
  against the previously derived **baseline creatinine** (12-month
  pre-transplant average) as the reference value.

### 3.AKI Event Grouping

- If an AKI event was within **7 days** of another AKI event, this was
  identified as a single (i.e., the same) event.

### 4.AKI Overlapping CKD

- AKI events identified in the previous step were not counted as an AKI
  event if they overlapped with a date that an identified the start of
  an episode of CKD.  
- However, AKI events could occur during an episode of CKD.

### 5.Identification of Acute Kidney Disease (AKD)

- **Acute Kidney Disease (AKD)** events were identified as AKI events
  lasting **\>7 consecutive days**.  
- However, the “AKI 1-year count” summary includes any AKD events in
  that total.

### 6.Defining “progression to CKD”

- For this context, the identified progression to sustained Stage
  3/3b/4/5 CKD is defined based on the [KDIGO criteria
  (2024)](https://www.sciencedirect.com/science/article/pii/S0085253823007664?via%3Dihub)
  with an additional criterion: having a sustained eGFR below threshold
  for at least 90 days, **and an average eGFR in the last 12 months of
  follow-up below such thresholds**.

- The thresholds as defined by
  [KDIGO](https://www.sciencedirect.com/science/article/pii/S0085253823007664?via%3Dihub)
  are:

  - **Stage 3**: \<60 ml/min/1.73m<sup>2</sup>
  - **Stage 3b**: \<45 ml/min/1.73m<sup>2</sup>
  - **Stage 4**: \<30 ml/min/1.73m<sup>2</sup>
  - **Stage 5**: \<15 ml/min/1.73m<sup>2</sup>

- The additional criterion of an average eGFR in the last 12 months of
  follow-up below such thresholds is to ensure our definition captured
  likely **irreversible CKD** stages within the islet transplant
  setting, in which kidney function can be very dynamic due to
  immunosuppression.

- In identified progressors, **time to progression** of each CKD stage
  was noted as the **beginning of the first episode where eGFR remained
  below threshold for ≥90 days**.

## Function outputs and suggested further uses

1.  Individual dataframes containing:

- **akiyear1**: Summary number of AKI events occurring in year 1 after
  transplant (or some defined baseline) for each patient ID
- **akiall**: Summary of every AKI event that occurred for the
  individual, containing the start and end time in days from baseline
  and the length of the event. If given a value of 0 there were no AKI
  events for that individual
- **dateprogression_fin**: Summary of AKI events over all follow up, the
  number of which were \>7 days and the identification of CKD
  progression and timing of progression in days with respect to
  baseline. (eGFR thresholds of 15, 30, 45, and 60)

2.  Summary table in a word document for serum creatinine measurement
    rates and frequencies called
    **SystemDate_number_of_creatinine_results_assessed.docx** that will
    be saved in the output directory you spcified in the function.

The dataframes can be downloaded as separate csv/xlsx files or taken on
for further analysis within your R script.

``` r
#Download the dateprogression_fin dataframe as a csv file
library(rio)

rio::export(dateprogression_fin,"your/output/directory/aki_and_ckd_progression.csv")
```

## Citation

If you use this package in your research, please cite it as:

> Alice Carr (2025). *kidneyoutcomes: Kidney Outcomes Analysis for
> Transplantation*.  
> GitHub: <https://github.com/alicelouisejane/kidneyoutcomes>.

You can also retrieve the citation in R using:

``` r
citation("kidneyoutcomes")
```
