
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
function over as below. The definitions of each of these variables are
also found below. **Please retain names of columns, pay attention to
units and coding for the sex variable**.

<table style="width:100%; table-layout:fixed; font-size:12px;">
<tr>
<th style="width:50%; text-align:center; font-size:14px;">
Input File Structure
</th>
<th style="width:50%; text-align:center; font-size:14px;">
Definitions of Variables in Input File
</th>
</tr>
<tr>
<td style="vertical-align: top; width:50%; padding: 10px; font-size:12px;">
<table style="width:100%; font-size:12px; border-collapse:collapse;">
<thead>
<tr>
<th style="text-align:right;">
pt_id
</th>
<th style="text-align:left;">
date_trans1
</th>
<th style="text-align:left;">
date_lab
</th>
<th style="text-align:right;">
age_at_lab
</th>
<th style="text-align:right;">
sex
</th>
<th style="text-align:right;">
creatinine_mgdl
</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align:right;">
12345
</td>
<td style="text-align:left;">
2014-07-25
</td>
<td style="text-align:left;">
2014-07-25
</td>
<td style="text-align:right;">
52.60274
</td>
<td style="text-align:right;">
1
</td>
<td style="text-align:right;">
0.88
</td>
</tr>
<tr>
<td style="text-align:right;">
12345
</td>
<td style="text-align:left;">
2014-07-25
</td>
<td style="text-align:left;">
2014-07-26
</td>
<td style="text-align:right;">
52.60548
</td>
<td style="text-align:right;">
1
</td>
<td style="text-align:right;">
1.04
</td>
</tr>
<tr>
<td style="text-align:right;">
12345
</td>
<td style="text-align:left;">
2014-07-25
</td>
<td style="text-align:left;">
2014-07-27
</td>
<td style="text-align:right;">
52.60822
</td>
<td style="text-align:right;">
1
</td>
<td style="text-align:right;">
1.30
</td>
</tr>
<tr>
<td style="text-align:right;">
12345
</td>
<td style="text-align:left;">
2014-07-25
</td>
<td style="text-align:left;">
2014-07-28
</td>
<td style="text-align:right;">
52.61096
</td>
<td style="text-align:right;">
1
</td>
<td style="text-align:right;">
1.43
</td>
</tr>
<tr>
<td style="text-align:right;">
12345
</td>
<td style="text-align:left;">
2014-07-25
</td>
<td style="text-align:left;">
2014-07-29
</td>
<td style="text-align:right;">
52.61370
</td>
<td style="text-align:right;">
1
</td>
<td style="text-align:right;">
1.38
</td>
</tr>
<tr>
<td style="text-align:right;">
12345
</td>
<td style="text-align:left;">
2014-07-25
</td>
<td style="text-align:left;">
2014-07-30
</td>
<td style="text-align:right;">
52.61917
</td>
<td style="text-align:right;">
1
</td>
<td style="text-align:right;">
1.33
</td>
</tr>
</tbody>
</table>
</td>
<td style="vertical-align: top; width:50%; padding: 10px; font-size:12px;">
<table style="width:100%; font-size:12px; border-collapse:collapse;">
<thead>
<tr>
<th style="text-align:left;">
Variable Name
</th>
<th style="text-align:left;">
Definition
</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align:left;">
pt_id
</td>
<td style="text-align:left;">
Patient ID
</td>
</tr>
<tr>
<td style="text-align:left;">
date_trans1
</td>
<td style="text-align:left;">
Date of first transaplant or date of "baseline" for that individual ie.
study entry. Format must be YYYY-MM-DD
</td>
</tr>
<tr>
<td style="text-align:left;">
date_lab
</td>
<td style="text-align:left;">
Date of creatinine measurement.
</td>
</tr>
<tr>
<td style="text-align:left;">
age_at_lab
</td>
<td style="text-align:left;">
Age at current lab date previously calculated ie. from patients date of
birth and the date_lab variable
</td>
</tr>
<tr>
<td style="text-align:left;">
sex
</td>
<td style="text-align:left;">
Sex coding males =1 and females=2
</td>
</tr>
<tr>
<td style="text-align:left;">
creatinine_mgdl
</td>
<td style="text-align:left;">
Value of creatinine result in mg/dl
</td>
</tr>
</tbody>
</table>
</td>
</tr>
</table>

## Identification of AKI and CKD in the Islet transplanation context

This function calculates the [CKD-EPI
2021](https://www.kidney.org/ckd-epi-creatinine-equation-2021-0) derived
eGFR per individual from the serum creatinine, age at lab, and sex.

### 1.Identification of CKD Episodes

- Episodes of CKD are first identified based on the [KDIGO
  criteria](https://www.sciencedirect.com/science/article/pii/S0085253823007664?via%3Dihub)
  as sustained eGFR below threshold for at least **90 days**.

### 2. Definition of AKI

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

### 3. AKI Event Grouping

- If an AKI event was within **7 days** of another AKI event, this was
  identified as a single (i.e., the same) event.

### 4. AKI Overlapping CKD

- AKI events identified in the previous step were not counted as an AKI
  event if they overlapped with a date that an identified the start of
  an episode of CKD.  
- However, AKI events could occur during an episode of CKD.

### 5. Identification of Acute Kidney Disease (AKD)

- **Acute Kidney Disease (AKD)** events were identified as AKI events
  lasting **\>7 consecutive days**.  
- However, the “AKI 1-year count” summary includes any AKD events in
  that total.

### 6. Defining “progression to CKD”

- For this context, the identified progression to sustained Stage
  3/3b/4/5 CKD is defined based on the [KDIGO criteria
  (2024)](https://www.sciencedirect.com/science/article/pii/S0085253823007664?via%3Dihub)
  with an additional criterion: having a sustained eGFR below threshold
  for at least 90 days, **and an average eGFR in the last 6 months of
  follow-up below such thresholds**.

- The thresholds as defined by
  [KDIGO](https://www.sciencedirect.com/science/article/pii/S0085253823007664?via%3Dihub)
  are:

  - **Stage 3**: \<60 ml/min/1.73m<sup>2</sup>
  - **Stage 3b**: \<45 ml/min/1.73m<sup>2</sup>
  - **Stage 4**: \<30 ml/min/1.73m<sup>2</sup>
  - **Stage 5**: \<15 ml/min/1.73m<sup>2</sup>

- The additional criterion of an average eGFR in the last 6 months of
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

Definitions of each of the variables for the data frames are below:

<table style="width:100%; table-layout:fixed; font-size:12px;">
<tr>
<th style="width:33%; text-align:center; font-size:12px;">
Definitions of variables in akiyear1 dataframe
</th>
<th style="width:33%; text-align:center; font-size:12px;">
Definitions of variables in akiall dataframe
</th>
<th style="width:33%; text-align:center; font-size:12px;">
Definitions of variables in progression dataframe
</th>
</tr>
<tr>
<td style="vertical-align: top; width:33%; padding: 10px; font-size:12px;">
<table style="width:100%; font-size:12px; border-collapse:collapse;">
<thead>
<tr>
<th style="text-align:left;">
Variable Name
</th>
<th style="text-align:left;">
Definition
</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align:left;">
pt_id
</td>
<td style="text-align:left;">
Patient ID
</td>
</tr>
<tr>
<td style="text-align:left;">
akiyear1_sum
</td>
<td style="text-align:left;">
Number of AKI events within 1 year from baseline (includes AKD events)
</td>
</tr>
</tbody>
</table>
</td>
<td style="vertical-align: top; width:33%; padding: 10px; font-size:12px;">
<table style="width:100%; font-size:12px; border-collapse:collapse;">
<thead>
<tr>
<th style="text-align:left;">
Variable Name
</th>
<th style="text-align:left;">
Definition
</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align:left;">
pt_id
</td>
<td style="text-align:left;">
Patient ID
</td>
</tr>
<tr>
<td style="text-align:left;">
values
</td>
<td style="text-align:left;">
AKI event (1 is event, if 0 that means there are no AKI events for this
individual)
</td>
</tr>
<tr>
<td style="text-align:left;">
start_tft
</td>
<td style="text-align:left;">
Start of event (days from baseline)
</td>
</tr>
<tr>
<td style="text-align:left;">
stop_tft
</td>
<td style="text-align:left;">
End of event (days from baseline)
</td>
</tr>
<tr>
<td style="text-align:left;">
diff
</td>
<td style="text-align:left;">
Length of event (days)
</td>
</tr>
</tbody>
</table>
</td>
<td style="vertical-align: top; width:33%; padding: 10px; font-size:12px;">
<table style="width:100%; font-size:12px; border-collapse:collapse;">
<thead>
<tr>
<th style="text-align:left;">
Variable Name
</th>
<th style="text-align:left;">
Definition
</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align:left;">
pt_id
</td>
<td style="text-align:left;">
Patient ID
</td>
</tr>
<tr>
<td style="text-align:left;">
maxfollowuptime
</td>
<td style="text-align:left;">
Total follow up time
</td>
</tr>
<tr>
<td style="text-align:left;">
akinhs_total_count
</td>
<td style="text-align:left;">
Number of AKI events counted over all follow up. AKI defined by KDIGO
and implemented using logic of the NHS algorithm. See above
</td>
</tr>
<tr>
<td style="text-align:left;">
akinhslonger7days_count
</td>
<td style="text-align:left;">
Number of AKI events that were \> 7days ie. would classify as AKD
</td>
</tr>
<tr>
<td style="text-align:left;">
last6months
</td>
<td style="text-align:left;">
Mean eGFR in the last 6 months of follow up
</td>
</tr>
<tr>
<td style="text-align:left;">
last12months
</td>
<td style="text-align:left;">
Mean eGFR in the last 12 months of follow up
</td>
</tr>
<tr>
<td style="text-align:left;">
followupunder45
</td>
<td style="text-align:left;">
Identifier for if mean eGFR in the last 6 months of follow up was under
45
</td>
</tr>
<tr>
<td style="text-align:left;">
followupunder30
</td>
<td style="text-align:left;">
Identifier for if mean eGFR in the last 6 months of follow up was under
30
</td>
</tr>
<tr>
<td style="text-align:left;">
followupunder15
</td>
<td style="text-align:left;">
Identifier for if mean eGFR in the last 6 months of follow up was under
15
</td>
</tr>
<tr>
<td style="text-align:left;">
followupunder60
</td>
<td style="text-align:left;">
Identifier for if mean eGFR in the last 6 months of follow up was under
60
</td>
</tr>
<tr>
<td style="text-align:left;">
sustained90day_30
</td>
<td style="text-align:left;">
Identifier for eGFR dropped below 30 for a 90 day period ie. CKD
</td>
</tr>
<tr>
<td style="text-align:left;">
sustained90day_15
</td>
<td style="text-align:left;">
Identifier for eGFR dropped below 15 for a 90 day period ie. CKD
</td>
</tr>
<tr>
<td style="text-align:left;">
sustained90day_45
</td>
<td style="text-align:left;">
Identifier for eGFR dropped below 45 for a 90 day period ie. CKD
</td>
</tr>
<tr>
<td style="text-align:left;">
sustained90day_60
</td>
<td style="text-align:left;">
Identifier for eGFR dropped below 60 for a 90 day period ie. CKD
</td>
</tr>
<tr>
<td style="text-align:left;">
ckd45_progression
</td>
<td style="text-align:left;">
Identifier of having stage 3b progression event defined by
sustained90day_45 = 1 and followupunder45=1
</td>
</tr>
<tr>
<td style="text-align:left;">
ckd30_progression
</td>
<td style="text-align:left;">
Identifier of having stage 4 progression event defined by
sustained90day_30 = 1 and followupunder30=1
</td>
</tr>
<tr>
<td style="text-align:left;">
ckd15_progression
</td>
<td style="text-align:left;">
Identifier of having stage 5 (ESKD) progression event defined by
sustained90day_15 = 1 and followupunder15=1
</td>
</tr>
<tr>
<td style="text-align:left;">
ckd60_progression
</td>
<td style="text-align:left;">
Identifier of having stage 3 progression event defined by
sustained90day_60 = 1 and followupunder60=1
</td>
</tr>
<tr>
<td style="text-align:left;">
persontimedays_45
</td>
<td style="text-align:left;">
Time in days to first stage 3b progression event with respect to some
baseline (ie. first transplant). If 0 this value is given the value of
the patients follow up time
</td>
</tr>
<tr>
<td style="text-align:left;">
persontimedays_30
</td>
<td style="text-align:left;">
Time in days to first stage 4 progression event with respect to some
baseline (ie. first transplant). If 0 this value is given the value of
the patients follow up time
</td>
</tr>
<tr>
<td style="text-align:left;">
persontimedays_15
</td>
<td style="text-align:left;">
Time in days to first stage 5 (ESKD) progression event with respect to
some baseline (ie. first transplant). If 0 this value is given the value
of the patients follow up time
</td>
</tr>
<tr>
<td style="text-align:left;">
persontimedays_60
</td>
<td style="text-align:left;">
Time in days to first stage 3 progression event with respect to some
baseline (ie. first transplant). If 0 this value is given the value of
the patients follow up time
</td>
</tr>
<tr>
<td style="text-align:left;">
persontimedays_30_notadjusted
</td>
<td style="text-align:left;">
Time in days to first sustained over 90 days event (egfr\<30) without
the additional criteria of a last 6 month mean egfr below threshold.
Time is with respect to some baseline (ie. first transplant)
</td>
</tr>
<tr>
<td style="text-align:left;">
persontimedays_60_notadjusted
</td>
<td style="text-align:left;">
Time in days to first sustained over 90 days event (egfr\<60) without
the additional criteria of a last 6 month mean egfr below threshold.
Time is with respect to some baseline (ie. first transplant)
</td>
</tr>
<tr>
<td style="text-align:left;">
persontimedays_15_notadjusted
</td>
<td style="text-align:left;">
Time in days to first sustained over 90 days event (egfr\<15) without
the additional criteria of a last 6 month mean egfr below threshold.
Time is with respect to some baseline (ie. first transplant)
</td>
</tr>
<tr>
<td style="text-align:left;">
persontimedays_45_notadjusted
</td>
<td style="text-align:left;">
Time in days to first sustained over 90 days event (egfr\<45) without
the additional criteria of a last 6 month mean egfr below threshold.
Time is with respect to some baseline (ie. first transplant)
</td>
</tr>
</tbody>
</table>
</td>
</tr>
</table>

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
