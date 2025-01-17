#' @title kidneyoutcomesintx
#'
#' @description
#' Processes serum creatinine data to identify Acute Kidney Injury (AKI) events
#' and progression to Chronic Kidney Disease (CKD) stages within a defined
#' baseline context. Developed for use in islet transplantation but adaptable
#' for other settings.
#'
#' @details
#' The function requires an input file containing specific variables:
#' - `pt_id`: Unique patient identifier.
#' - `date_trans1`: Date of the first transplant/study entry, used as the "baseline" date.
#' - `date_lab`: Date of the serum creatinine laboratory result.
#' - `sex`: Define 1 for male, 2 for female.
#' - `age_at_lab`: Age of the patient at the laboratory date (in years).
#' - `creatinine_mgdl`: Serum creatinine levels (Units MUST BE mg/dL).
#'
#' @param inputdataframe Data frame. Name of loaded dataframe containing the variales pt_id,	date_trans1,	date_lab,	sex,age_at_lab,creatinine_mgdl. See README for details.
#' @param outputdirectory Character. The path to the output directory where results will be saved.
#'
#' @returns
#' Individual dataframes containing:
#' - Summary number of AKI events occurring in year 1 after transplant (or some defined baseline) for each patient ID
#' - Summary of every AKI event that occurred for the individual, containing the start and end time in days from baseline and the length of the event. If given a value of 0 there were no AKI events for that individual
#' - Summary of AKI events over all follow up, the number of which were >7 days and the identification of CKD progression and timing of progression in days with respect to baseline. (eGFR thresholds of 15, 30, 45, and 60)
#'
#' and finally a summary table in a word document for serum creatinine measurement rates and frequencies.
#'
#' @import dplyr
#' @import rio
#' @import gtsummary
#' @import lubridate
#' @import tidyr
#' @import RcppRoll
#' @import zoo
#' @import forecastML
#' @import imputeTS
#'
#' @examples
#' \dontrun{
#' kidneyoutcomesintx("path/to/input.csv", "path/to/output/")
#' }
#'
#' @author
#' Alice Carr
#'
#' @keywords kidney outcomes AKI CKD transplant
#' @export

kidneyoutcomesintx <- function(inputdataframe,
                               outputdirectory) {
  #Import appropriate dataframe
  # no missing creatinine values
  # must contain variables -> pt_id,	date_trans1,	date_lab,	sex,age_at_lab,creatinine_mgdl
  # dates must be formatted as YYYY-MM-DD
  # date_trans1 can be a "baseline" date for that person ie. date of first transplant/study entry etc.- meaning it could be used outside of Tx tracking
  # must specify the column location of your lab date variable

  data <- inputdataframe

  # Specify the required variables
  required_variables <- c("pt_id",
                          "date_trans1",
                          "date_lab",
                          "sex",
                          "age_at_lab",
                          "creatinine_mgdl")

  # Check if all required variables are in the dataset
  missing_vars <- setdiff(required_variables, names(data))

  if (length(missing_vars) == 0) {
    message("All required variables are present in the dataset.")
  } else {
    warning(
      "The following required variables are missing: ",
      paste(missing_vars, collapse = ", ")
    )
    stop("Execution halted due to missing required variables.")
  }

  timetoegfr <- data %>%
    #select the variables which will ensure the date_lab is in colum location 3 required for next steps
    select(c("pt_id",
             "date_trans1",
             "date_lab",
             "sex",
             "age_at_lab",
             "creatinine_mgdl")) %>%
    dplyr::mutate(across(pt_id, as.character)) %>%
    dplyr::mutate(across(date_trans1, lubridate::ymd)) %>%
    dplyr::mutate(across(date_lab, lubridate::ymd)) %>%
    dplyr::mutate(across(age_at_lab, as.numeric)) %>%
    dplyr::mutate(across(creatinine_mgdl, as.numeric)) %>%
    dplyr::mutate(across(sex, as.factor)) %>%
    #create time from "baseline" date variable variable
    dplyr::mutate(timefromtransplant1 = as.numeric(difftime(date_lab, date_trans1, units = "days"))) %>%
    dplyr::mutate(timefromtransplant1_mo = timefromtransplant1 / 30.417) %>%
    # calculate CKD-EPI eGFR using 2021 equation
    dplyr::mutate(kappa = ifelse(sex == 1, 0.9, ifelse(sex == 2, 0.7, NA))) %>%
    dplyr::mutate(alpha = ifelse(sex == 1, -0.302 , ifelse(sex == 2, -0.241, NA))) %>%
    dplyr::mutate(conts = ifelse(sex == 1, 1 , ifelse(sex == 2, 1.012, NA))) %>%
    dplyr::mutate(
      ckdegfr = 142 * ifelse(creatinine_mgdl / kappa > 1, 1, creatinine_mgdl / kappa) ^
        alpha *
        ifelse(creatinine_mgdl / kappa < 1, 1, creatinine_mgdl / kappa) ^
        -1.200 *
        0.9938 ^ age_at_lab * conts
    ) %>%
    dplyr::select(-c(kappa, alpha, conts, age_at_lab, sex)) %>%
    dplyr::filter(!is.na(ckdegfr))


  #####
  #Identify AKI
  #####
  aki <- timetoegfr %>%
    dplyr::group_by(pt_id) %>%
    dplyr::arrange(date_lab) %>%
    dplyr::mutate(creatinine_umoll = creatinine_mgdl * 88.4) %>%
    dplyr::mutate(baseline_creatinine_umoll = mean(creatinine_umoll[timefromtransplant1 ==
                                                                      0], na.rm = T)) %>% # create variable for baseline trnsplant
    dplyr::filter(timefromtransplant1 != 0) %>% # remove baseline creatinine to not get it included in post transplant medians
    forecastML::fill_gaps(
      .,
      date_col = 3,
      frequency = "1 day",
      groups = "pt_id",
      static_features = NULL
    ) %>%
    dplyr::group_by(pt_id) %>%
    tidyr::fill(c(date_trans1, baseline_creatinine_umoll), .direction = "updown") %>%
    dplyr::group_by(pt_id) %>%
    #7 days pre or post index
    dplyr::mutate(rolling_min7days_before = RcppRoll::roll_min(
      lag(creatinine_umoll),
      7,
      align = "right",
      fill = NA,
      na.rm = T
    )) %>% # find the minimum value in the previous 7 days
    dplyr::mutate(rolling_min7days_after = RcppRoll::roll_min(
      lead(creatinine_umoll),
      7,
      align = "left",
      fill = NA,
      na.rm = T
    )) %>% # find the minimum value in the previous 7 days
    dplyr::mutate(
      rolling_min7days_before = ifelse(rolling_min7days_before == Inf, NA, rolling_min7days_before)
    )  %>% # where a reading does not have any labs in the 7 days prior make it missing
    dplyr::mutate(
      rolling_min7days_after = ifelse(rolling_min7days_after == Inf, NA, rolling_min7days_after)
    )  %>% # where a reading does not have any labs in the 7 days prior make it missing

    #make anything in the first 7 days comparable to pre transplant creatinine
    dplyr::mutate(
      rolling_min7days_before = ifelse(
        date_lab <= (date_trans1 + days(7)),
        baseline_creatinine_umoll,
        rolling_min7days_before
      )
    ) %>%
    dplyr::mutate(
      rolling_min7days_after = ifelse(
        date_lab <= (date_trans1 + days(7)),
        baseline_creatinine_umoll,
        rolling_min7days_after
      )
    ) %>%

    dplyr::mutate(rolling_min7days_before = ifelse(is.na(creatinine_umoll), NA, rolling_min7days_before)) %>%
    dplyr::mutate(rolling_min7days_after = ifelse(is.na(creatinine_umoll), NA, rolling_min7days_after)) %>%

    # 48hrs pre or post index
    dplyr::mutate(Value_one_Row_ahead = lead(creatinine_umoll, 1)) %>%
    dplyr::mutate(Value_one_Row_behind = lag(creatinine_umoll, 1)) %>%
    dplyr::mutate(Value_one_Row_ahead = ifelse(is.na(creatinine_umoll), NA, Value_one_Row_ahead)) %>%
    dplyr::mutate(Value_one_Row_behind = ifelse(is.na(creatinine_umoll), NA, Value_one_Row_behind)) %>%
    dplyr::mutate(Value_Two_Rows_ahead = lead(creatinine_umoll, 2)) %>%
    dplyr::mutate(Value_Two_Rows_ahead = ifelse(is.na(creatinine_umoll), NA, Value_Two_Rows_ahead)) %>%
    dplyr::mutate(Value_Two_Rows_behind = lag(creatinine_umoll, 2)) %>%
    dplyr::mutate(Value_Two_Rows_behind = ifelse(is.na(creatinine_umoll), NA, Value_Two_Rows_behind)) %>%
    dplyr::mutate(
      mincreat48hrspre = ifelse(
        !is.na(Value_one_Row_behind) &
          !is.na(Value_Two_Rows_behind) &
          Value_Two_Rows_behind >= Value_one_Row_behind,
        Value_one_Row_behind,
        ifelse(
          !is.na(Value_one_Row_behind) &
            !is.na(Value_Two_Rows_behind) &
            Value_Two_Rows_behind <= Value_one_Row_behind,
          Value_Two_Rows_behind,
          ifelse(
            is.na(Value_Two_Rows_behind) &
              !is.na(Value_one_Row_behind) ,
            Value_one_Row_behind,
            ifelse(
              is.na(Value_one_Row_behind) &
                !is.na(Value_Two_Rows_behind),
              Value_Two_Rows_behind,
              ifelse(
                is.na(Value_Two_Rows_behind) &
                  is.na(Value_Two_Rows_behind),
                NA,
                NA
              )
            )
          )
        )
      )
    ) %>%
    dplyr::mutate(
      mincreat48hrspost = ifelse(
        !is.na(Value_one_Row_ahead) &
          !is.na(Value_Two_Rows_ahead) &
          Value_Two_Rows_ahead >= Value_one_Row_ahead,
        Value_one_Row_ahead,
        ifelse(
          !is.na(Value_one_Row_ahead) &
            !is.na(Value_Two_Rows_ahead) &
            Value_Two_Rows_ahead <= Value_one_Row_ahead,
          Value_Two_Rows_ahead,
          ifelse(
            is.na(Value_Two_Rows_ahead) &
              !is.na(Value_one_Row_ahead) ,
            Value_one_Row_ahead,
            ifelse(
              is.na(Value_one_Row_ahead) &
                !is.na(Value_Two_Rows_ahead),
              Value_Two_Rows_ahead,
              ifelse(
                is.na(Value_Two_Rows_ahead) &
                  is.na(Value_Two_Rows_ahead),
                NA,
                NA
              )
            )
          )
        )
      )
    ) %>%
    dplyr::mutate(
      mincreat48hrspreandpost = ifelse(
        !is.na(mincreat48hrspre) &
          !is.na(mincreat48hrspost) &
          mincreat48hrspost >= mincreat48hrspre,
        mincreat48hrspre,
        ifelse(
          !is.na(mincreat48hrspre) &
            !is.na(mincreat48hrspost) &
            mincreat48hrspost <= mincreat48hrspre,
          mincreat48hrspost,
          ifelse(
            !is.na(mincreat48hrspre) &
              is.na(mincreat48hrspost),
            mincreat48hrspre,
            ifelse(
              !is.na(mincreat48hrspost) &
                is.na(mincreat48hrspre),
              mincreat48hrspost,
              ifelse(is.na(mincreat48hrspost) &
                       is.na(mincreat48hrspre), NA, NA)
            )
          )
        )
      )
    ) %>%
    dplyr::mutate(mincreat48hrspre = ifelse(
      date_lab <= (date_trans1 + days(7)),
      baseline_creatinine_umoll,
      mincreat48hrspre
    )) %>%
    dplyr::mutate(mincreat48hrspost = ifelse(
      date_lab <= (date_trans1 + days(7)),
      baseline_creatinine_umoll,
      mincreat48hrspost
    )) %>%
    dplyr::mutate(
      mincreat48hrspreandpost = ifelse(
        date_lab <= (date_trans1 + days(7)),
        baseline_creatinine_umoll,
        mincreat48hrspreandpost
      )
    ) %>%
    dplyr::mutate(
      mincreat7dayspreandpost = ifelse(
        !is.na(rolling_min7days_before) &
          !is.na(rolling_min7days_after) &
          rolling_min7days_after >= rolling_min7days_before,
        rolling_min7days_before,
        ifelse(
          !is.na(rolling_min7days_before) &
            !is.na(rolling_min7days_after) &
            rolling_min7days_after <= rolling_min7days_before,
          rolling_min7days_after,
          ifelse(
            !is.na(rolling_min7days_before) &
              is.na(rolling_min7days_after),
            rolling_min7days_before,
            ifelse(
              !is.na(rolling_min7days_after) &
                is.na(rolling_min7days_before),
              rolling_min7days_after,
              ifelse(
                is.na(rolling_min7days_after) &
                  is.na(rolling_min7days_before),
                NA,
                NA
              )
            )
          )
        )
      )
    ) %>%
    dplyr::mutate(
      creatrisewithinhours48pre = ifelse(
        !is.na(mincreat48hrspre) &
          creatinine_umoll - mincreat48hrspre > 26,
        1,
        NA
      )
    ) %>%
    dplyr::mutate(
      creatrisewithinhours48prepost = ifelse(
        !is.na(mincreat48hrspreandpost) &
          creatinine_umoll - mincreat48hrspreandpost > 26,
        1,
        NA
      )
    ) %>%
    dplyr::mutate(
      increase1.5in7dayspre = ifelse(
        !is.na(rolling_min7days_before) &
          creatinine_umoll / rolling_min7days_before >= 1.5,
        1,
        NA
      )
    ) %>%
    dplyr::mutate(
      increase1.5in7daysprepost = ifelse(
        !is.na(mincreat7dayspreandpost) &
          creatinine_umoll / mincreat7dayspreandpost >= 1.5,
        1,
        NA
      )
    ) %>%
    dplyr::filter(!is.na(creatinine_umoll)) %>%
    dplyr::select(
      pt_id,
      date_lab,
      date_trans1,
      creatinine_umoll,
      mincreat48hrspre,
      mincreat48hrspost,
      mincreat48hrspreandpost,
      rolling_min7days_before,
      rolling_min7days_after,
      mincreat7dayspreandpost,
      creatrisewithinhours48pre,
      creatrisewithinhours48prepost,
      increase1.5in7dayspre,
      increase1.5in7daysprepost,
      contains("1.2")
    )

  akimedian <- timetoegfr %>%
    dplyr::group_by(pt_id) %>%
    dplyr::arrange(date_lab) %>%
    dplyr::mutate(creatinine_umoll = creatinine_mgdl * 88.4) %>%
    dplyr::mutate(baseline_creatinine_umoll = mean(creatinine_umoll[timefromtransplant1 ==
                                                                      0], na.rm = T)) %>% # create variable for baseline trnsplant
    dplyr::filter(timefromtransplant1 != 0) %>% # remove baseline creatinine to not get it included in post transplant medians
    forecastML::fill_gaps(
      .,
      date_col = 3,
      frequency = "1 day",
      groups = "pt_id",
      static_features = NULL
    ) %>%
    dplyr::group_by(pt_id) %>%
    tidyr::fill(c(date_trans1, baseline_creatinine_umoll), .direction = "updown")  %>%
    dplyr::select(pt_id,
                  date_lab,
                  creatinine_umoll,
                  date_trans1,
                  timefromtransplant1_mo) %>%
    dplyr::filter(!is.na(creatinine_umoll)) %>%
    dplyr::group_by(pt_id) %>%
    dplyr::mutate(previousresult_datediff = as.numeric(difftime(date_lab, lag(date_lab)))) %>%
    dplyr::mutate(postresult_datediff = as.numeric(difftime(lead(date_lab), date_lab))) %>%
    #mutate(creatinine_umoll=ifelse(date_lab<(date_trans1+days(7)),NA,creatinine_umoll)) %>%
    dplyr::mutate(
      includeinmedian_pre = ifelse(
        previousresult_datediff >= 8 &
          previousresult_datediff <= 365,
        1,
        NA
      )
    ) %>%
    dplyr::mutate(includeinmedian_post = ifelse(postresult_datediff >= 8 &
                                                  postresult_datediff <= 365, 1, NA)) %>%

    forecastML::fill_gaps(
      .,
      date_col = 2,
      frequency = "1 day",
      groups = "pt_id",
      static_features = NULL
    ) %>%
    #select(pt_id,date_lab, date_trans1, includeinmedian_pre,includeinmedian_post,creatinine_formedian) %>%
    dplyr::group_by(pt_id) %>%
    dplyr::mutate(rolling_median_pre = ifelse(
      includeinmedian_pre == 1,
      zoo::rollapply(
        creatinine_umoll,
        width = 365,
        FUN = median,
        na.rm = T,
        align = "right",
        fill = NA,
        partial = T
      ),
      NA
    )) %>%
    dplyr::mutate(rolling_median_post = ifelse(
      includeinmedian_post == 1,
      zoo::rollapply(
        creatinine_umoll,
        width = 365,
        FUN = median,
        na.rm = T,
        align = "left",
        fill = NA,
        partial = T
      ),
      NA
    )) %>%
    dplyr::filter(!is.na(creatinine_umoll)) %>%
    dplyr::select(
      pt_id,
      date_lab,
      timefromtransplant1_mo,
      creatinine_umoll,
      previousresult_datediff,
      postresult_datediff,
      rolling_median_pre,
      rolling_median_post
    ) %>%
    dplyr::mutate(increase1.5medianpre = ifelse(
      !is.na(rolling_median_pre) &
        creatinine_umoll / rolling_median_pre >= 1.5,
      1,
      NA
    )) %>%
    dplyr::mutate(
      increase1.5medianpost = ifelse(
        !is.na(rolling_median_post) &
          creatinine_umoll / rolling_median_post >= 1.5,
        1,
        NA
      )
    )

  numberofscrassessed <- akimedian %>%
    dplyr::group_by(pt_id) %>%
    dplyr::mutate(previousresult_datediff_meanperperson = mean(previousresult_datediff, na.rm =
                                                                 T)) %>%
    dplyr::mutate(ncreatperperson = length(creatinine_umoll)) %>%
    dplyr::mutate(maxtime = max(timefromtransplant1_mo, na.rm = T)) %>%
    dplyr::mutate(ratemeasure = ncreatperperson / maxtime) %>%
    dplyr::select(
      pt_id,
      previousresult_datediff_meanperperson,
      ncreatperperson,
      maxtime,
      ratemeasure
    ) %>%
    unique() %>%
    gtsummary::tbl_summary(
      include = -pt_id,
      label = list(
        previousresult_datediff_meanperperson ~ "Mean number of days of previous results",
        ncreatperperson ~ "Number of creatinine results assessed",
        maxtime ~ "Total follow up time of all results (months)",
        ratemeasure ~ "Rate of measurement (Number of creatinine results/Total follow up time)"
      )
    )


  aki_final <- merge(
    aki,
    akimedian,
    by = c("pt_id", "date_lab", "creatinine_umoll"),
    all = T
  ) %>%
    dplyr::filter(!is.na(creatinine_umoll)) %>%
    dplyr::mutate(aki_NHS = ifelse(
      creatrisewithinhours48pre == 1 | increase1.5in7dayspre == 1,
      1,
      NA
    )) %>%
    #mutate(aki_Hapcamodified=ifelse(creatrisewithinhours48prepost==1|increase1.5in7daysprepost==1,1,NA)) %>%
    dplyr::mutate(aki_NHS = ifelse(is.na(aki_NHS) &
                                     increase1.5medianpre == 1, 1, aki_NHS)) %>%
    #mutate(aki_Hapcamodified=ifelse(is.na(aki_Hapcamodified) & increase1.5medianpost==1,1,aki_Hapcamodified)) %>%
    #mutate(aki_Hapcamodified=ifelse(is.na(aki_Hapcamodified) & increase1.5medianpre==1,1,aki_Hapcamodified)) %>%
    dplyr::arrange(pt_id, date_lab)


  #akistartend
  #in a dataset which is an imputed timeseries of every day since first post transplant labs
  #we identify where there is an aki, if there is an aki <7 rows apart (days apart) then we would infill the "gap"
  #between these  these together with a 1 to have this as the run length of the AKI. If there are
  #An AKI for >7 days is AKD.
  #There should not be an issue within overlapping CKD periods and AKI :
  #you can still be <60 and have an AKI in this dataset because there is frequent follow up (transplant context)
  #however need to make sure that AKIs are not defined when we have defined the start of a CKD episode (handled later)
  akitime <- aki_final %>%
    dplyr::select(pt_id, date_lab, aki_NHS) %>%
    #select(pt_id,date_lab,aki_NHS,aki_Hapcamodified) %>%
    forecastML::fill_gaps(
      .,
      date_col = 2,
      frequency = "1 day",
      groups = "pt_id",
      static_features = NULL
    )

  akitime2 <- akitime %>%
    dplyr::rename("aki_NHS_im" = "aki_NHS") %>%
    #rename("aki_NHS_im"="aki_NHS","aki_Hapcamodified_im"="aki_Hapcamodified") %>%
    imputeTS::na_kalman(.,
                        model = "auto.arima",
                        smooth = T,
                        maxgap = 7)

  akitimefinal <- merge(akitime, akitime2, all = T) %>%
    #mutate(aki_Hapcamodified_im=ifelse(aki_Hapcamodified_im==0,1,aki_Hapcamodified_im)) %>%
    dplyr::mutate(aki_NHS_im = ifelse(aki_NHS_im == 0, 1, aki_NHS_im))


  #identify time to egfr progression ie. time to CKD stages
  egfr.rle <- list()

  #define lists
  ids <- unique(timetoegfr$pt_id)
  dateprogression <- base::as.data.frame(base::matrix(nrow = 0, ncol = base::length(ids)))
  timeaki_tmerge <- list()
  ckdstartstop <- list()

  for (i in 1:length(ids)) {
    pt_id <- ids[i]
    print(paste0("running patient id: ", pt_id))
    egfr_surv <- timetoegfr %>%
      dplyr::filter(pt_id == ids[i]) %>%
      dplyr::arrange(timefromtransplant1_mo) %>%
      dplyr::mutate(progression45 = ifelse(ckdegfr < 45, 1, 0)) %>%
      dplyr::mutate(progression30 = ifelse(ckdegfr < 30, 1, 0)) %>%
      dplyr::mutate(progression15 = ifelse(ckdegfr < 15, 1, 0)) %>%
      dplyr::mutate(progression60 = ifelse(ckdegfr < 60, 1, 0)) %>%
      dplyr::filter(!is.na(date_trans1))

    aki_surv <- timetoegfr %>%
      dplyr::filter(pt_id == ids[i]) %>%
      dplyr::arrange(timefromtransplant1_mo) %>%
      dplyr::mutate(progression45 = ifelse(ckdegfr < 45, 1, 0)) %>%
      dplyr::mutate(progression30 = ifelse(ckdegfr < 30, 1, 0)) %>%
      dplyr::mutate(progression15 = ifelse(ckdegfr < 15, 1, 0)) %>%
      dplyr::mutate(progression60 = ifelse(ckdegfr < 60, 1, 0)) %>%
      merge(
        dplyr::filter(akitimefinal, pt_id == ids[i]),
        by = c("pt_id", "date_lab"),
        all = T
      ) %>%
      #mutate(aki_Hapcamodified_im=ifelse(is.na(aki_Hapcamodified_im),0,aki_Hapcamodified_im)) %>%
      dplyr::mutate(aki_NHS_im = ifelse(is.na(aki_NHS_im), 0, aki_NHS_im))

    egfr_surv$position <- row.names(egfr_surv)
    aki_surv$position <- row.names(aki_surv)


    time <- dplyr::select(
      egfr_surv,
      c(
        timefromtransplant1_mo,
        timefromtransplant1,
        date_lab,
        position,
        ckdegfr
      )
    )
    timeaki <- dplyr::select(
      aki_surv,
      c(
        timefromtransplant1_mo,
        timefromtransplant1,
        date_lab,
        position,
        ckdegfr
      )
    )


    # find the mean value of egfr in the last 6 and 12 months of follow up
    last6months <- time %>%
      dplyr::filter(timefromtransplant1_mo >= max(timefromtransplant1_mo, na.rm = T) -
                      6) %>%
      dplyr::summarise(mean6 = mean(ckdegfr))

    last12months <- time %>%
      dplyr::filter(timefromtransplant1_mo >= max(timefromtransplant1_mo, na.rm = T) -
                      12) %>%
      dplyr::summarise(mean12 = mean(ckdegfr))


    #aki hapca
    # x=aki_surv$aki_Hapcamodified_im
    # akihapcastart<-as.data.frame(rev(length(x)-cumsum(rle(rev(x))$lengths)[rle(rev(x))$values==1]+1)) %>%
    #   rename("position"=1) %>%
    #   mutate(values=1) %>%
    #   mutate(start_stop="start")
    #
    # akihapcastop<-as.data.frame(cumsum(rle(x)$lengths)[rle(x)$values==1]) %>%
    #   rename("position"=1) %>%
    #   mutate(values=1) %>%
    #   mutate(start_stop="stop")
    #
    # akihapcastopstart<-rbind(akihapcastart,akihapcastop) %>%
    #   arrange(position,start_stop)

    #aki NHS
    x = aki_surv$aki_NHS_im
    akinhsstart <- as.data.frame(rev(length(x) - cumsum(rle(rev(
      x
    ))$lengths)[rle(rev(x))$values == 1] + 1)) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "start")

    akinhsstop <- as.data.frame(cumsum(rle(x)$lengths)[rle(x)$values == 1]) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "stop")

    akinhsstopstart <- rbind(akinhsstart, akinhsstop) %>%
      dplyr::arrange(position, start_stop)




    #egfr 45
    x = egfr_surv$progression45
    egfr45locstart <- as.data.frame(rev(length(x) - cumsum(rle(rev(
      x
    ))$lengths)[rle(rev(x))$values == 1] + 1)) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "start")

    egfr45locstop <- as.data.frame(cumsum(rle(x)$lengths)[rle(x)$values ==
                                                            1]) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "stop")

    egfr45stopstart <- rbind(egfr45locstart, egfr45locstop) %>%
      dplyr::arrange(position, start_stop)




    #egfr 30
    x = egfr_surv$progression30
    egfr30locstart <- as.data.frame(rev(length(x) - cumsum(rle(rev(
      x
    ))$lengths)[rle(rev(x))$values == 1] + 1)) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "start")

    egfr30locstop <- as.data.frame(cumsum(rle(x)$lengths)[rle(x)$values ==
                                                            1]) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "stop")

    egfr30stopstart <- rbind(egfr30locstart, egfr30locstop) %>%
      dplyr::arrange(position, start_stop)


    # egfr 15
    x = egfr_surv$progression15
    egfr15locstart <- as.data.frame(rev(length(x) - cumsum(rle(rev(
      x
    ))$lengths)[rle(rev(x))$values == 1] + 1)) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "start")

    egfr15locstop <- as.data.frame(cumsum(rle(x)$lengths)[rle(x)$values ==
                                                            1]) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "stop")

    egfr15stopstart <- rbind(egfr15locstart, egfr15locstop) %>%
      dplyr::arrange(position, start_stop)


    # egfr 60
    x = egfr_surv$progression60
    egfr60locstart <- as.data.frame(rev(length(x) - cumsum(rle(rev(
      x
    ))$lengths)[rle(rev(x))$values == 1] + 1)) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "start")

    egfr60locstop <- as.data.frame(cumsum(rle(x)$lengths)[rle(x)$values ==
                                                            1]) %>%
      dplyr::rename("position" = 1) %>%
      dplyr::mutate(values = 1) %>%
      dplyr::mutate(start_stop = "stop")

    egfr60stopstart <- rbind(egfr60locstart, egfr60locstop) %>%
      dplyr::arrange(position, start_stop)


    # AKI hapca
    # if(length(akihapcastopstart$values)==0){
    #   akihapcaloc<-filter(akihapcastopstart,values>0)
    #   dateprogression["pt_id", i] <- pt_id
    #   dateprogression["akihapca_total_count", i] <- 0
    #   dateprogression["akihapcalonger7days_count", i] <- 0
    #
    #
    #
    # }else if(length(akihapcastopstart$values)>0){
    #   akihapcaloc <- akihapcastopstart %>%
    #     mutate(pt_id=ids[i]) %>%
    #     merge(timeaki,all.x=T) %>%
    #     dplyr::select(c(pt_id,start_stop,date_lab,values,timefromtransplant1)) %>%
    #     mutate(start_tft=ifelse(start_stop=="start",timefromtransplant1,NA)) %>%
    #     mutate(stop_tft=ifelse(start_stop=="stop",timefromtransplant1,NA)) %>%
    #     mutate(start=ifelse(start_stop=="start",ymd(date_lab),ymd(NA))) %>%
    #     mutate(stop=ifelse(start_stop=="stop",ymd(date_lab),ymd(NA)))%>%
    #     arrange(timefromtransplant1)%>%
    #     tidyr::fill(c(start,start_tft), .direction = "down") %>%
    #     tidyr::fill(c(stop,stop_tft), .direction = "up") %>%
    #     mutate(across(c(start,stop),as.Date)) %>%
    #     dplyr::select(-c(start_stop,date_lab,timefromtransplant1)) %>%
    #     unique() %>%
    #     mutate(diff=abs(as.numeric(difftime(start,stop, units = "days")))) %>%
    #     filter(diff<90)
    # }
    #
    #


    #AKI NHS
    if (length(akinhsstopstart$values) == 0) {
      akinhsloc <- dplyr::filter(akinhsstopstart, values > 0)
      dateprogression["pt_id", i] <- pt_id
      dateprogression["akinhs_total_count", i] <- 0
      dateprogression["akinhslonger7days_count", i] <- 0


    } else if (length(akinhsstopstart$values) > 0) {
      akinhsloc <- akinhsstopstart %>%
        dplyr::mutate(pt_id = ids[i]) %>%
        merge(timeaki, all.x = T) %>%
        dplyr::select(c(pt_id, start_stop, date_lab, values, timefromtransplant1)) %>%
        dplyr::mutate(start_tft = ifelse(start_stop == "start", timefromtransplant1, NA)) %>%
        dplyr::mutate(stop_tft = ifelse(start_stop == "stop", timefromtransplant1, NA)) %>%
        dplyr::mutate(start = ifelse(start_stop == "start", ymd(date_lab), ymd(NA))) %>%
        dplyr::mutate(stop = ifelse(start_stop == "stop", ymd(date_lab), ymd(NA))) %>%
        dplyr::arrange(timefromtransplant1) %>%
        tidyr::fill(c(start, start_tft), .direction = "down") %>%
        tidyr::fill(c(stop, stop_tft), .direction = "up") %>%
        dplyr::mutate(across(c(start, stop), as.Date)) %>%
        dplyr::select(-c(start_stop, date_lab, timefromtransplant1)) %>%
        unique() %>%
        dplyr::mutate(diff = abs(as.numeric(
          difftime(start, stop, units = "days")
        ))) %>%
        dplyr::filter(diff < 90)
    }


#  the following steps will populate the CKD progression dataframe containing start and end times of CKD stages
# either there will be no eGFR values at this CKD stage (the first part of the for loop) and the dataframe will populate with pt_id NA and the stage threshold
    if (length(egfr45stopstart$values) == 0) {
      under45loc <- dplyr::filter(egfr45stopstart, values > 0)
      dateprogression["pt_id", i] <- pt_id
      dateprogression["persontimedays_45", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
      dateprogression["sustained90day_30", i] <- 0
      ckd45all <- data.frame(pt_id = pt_id,
                             "start_tft" = NA,
                             "ckd" = 45)

    } else if (length(egfr45stopstart$values) > 0) {
      under45loc <- egfr45stopstart %>%
        dplyr::mutate(pt_id = ids[i]) %>%
        merge(time, all.x = T) %>%
        dplyr::select(c(pt_id, start_stop, date_lab, values, timefromtransplant1)) %>%
        dplyr::mutate(start_tft = ifelse(start_stop == "start", timefromtransplant1, NA)) %>%
        dplyr::mutate(stop_tft = ifelse(start_stop == "stop", timefromtransplant1, NA)) %>%
        dplyr::mutate(start = ifelse(start_stop == "start", ymd(date_lab), ymd(NA))) %>%
        dplyr::mutate(stop = ifelse(start_stop == "stop", ymd(date_lab), ymd(NA))) %>%
        dplyr::arrange(timefromtransplant1) %>%
        tidyr::fill(c(start, start_tft), .direction = "down") %>%
        tidyr::fill(c(stop, stop_tft), .direction = "up") %>%
        dplyr::mutate(across(c(start, stop), as.Date)) %>%
        dplyr::select(-c(start_stop, date_lab, timefromtransplant1)) %>%
        unique() %>%
        dplyr::mutate(diff = abs(as.numeric(
          difftime(start, stop, units = "days")
        ))) %>%
        dplyr::filter(diff >= 90)

      ckd45all <- dplyr::select(under45loc, pt_id, start_tft) %>%
        dplyr::mutate(ckd = 45)
    }


    if (length(egfr30stopstart$values) == 0) {
      under30loc <- dplyr::filter(egfr30stopstart, values > 0)
      dateprogression["pt_id", i] <- pt_id
      dateprogression["persontimedays_30", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
      dateprogression["sustained90day_30", i] <- 0
      ckd30all <- data.frame(pt_id = pt_id,
                             "start_tft" = NA,
                             "ckd" = 30)

    } else if (length(egfr30stopstart$values) > 0) {
      under30loc <- egfr30stopstart %>%
        dplyr::mutate(pt_id = ids[i]) %>%
        merge(time, all.x = T) %>%
        dplyr::select(c(pt_id, start_stop, date_lab, values, timefromtransplant1)) %>%
        dplyr::mutate(start_tft = ifelse(start_stop == "start", timefromtransplant1, NA)) %>%
        dplyr::mutate(stop_tft = ifelse(start_stop == "stop", timefromtransplant1, NA)) %>%
        dplyr::mutate(start = ifelse(start_stop == "start", ymd(date_lab), ymd(NA))) %>%
        dplyr::mutate(stop = ifelse(start_stop == "stop", ymd(date_lab), ymd(NA))) %>%
        dplyr::arrange(timefromtransplant1) %>%
        tidyr::fill(c(start, start_tft), .direction = "down") %>%
        tidyr::fill(c(stop, stop_tft), .direction = "up") %>%
        dplyr::mutate(across(c(start, stop), as.Date)) %>%
        dplyr::select(-c(start_stop, date_lab, timefromtransplant1)) %>%
        unique() %>%
        dplyr::mutate(diff = abs(as.numeric(
          difftime(start, stop, units = "days")
        ))) %>%
        dplyr::filter(diff >= 90)

      ckd30all <- dplyr::select(under30loc, pt_id, start_tft) %>%
        dplyr::mutate(ckd = 30)
    }

    if (length(egfr15stopstart$values) == 0) {
      under15loc <- dplyr::filter(egfr15stopstart, values > 0)
      dateprogression["pt_id", i] <- pt_id
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
      dateprogression["persontimedays_15", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["sustained90day_15", i] <- 0
      ckd15all <- data.frame(pt_id = pt_id,
                             "start_tft" = NA,
                             "ckd" = 15)

    } else if (length(egfr15stopstart$values) > 0) {
      under15loc <- egfr15stopstart %>%
        dplyr::mutate(pt_id = ids[i]) %>%
        merge(time, all.x = T) %>%
        dplyr::select(c(pt_id, start_stop, date_lab, values, timefromtransplant1)) %>%
        dplyr::mutate(start_tft = ifelse(start_stop == "start", timefromtransplant1, NA)) %>%
        dplyr::mutate(stop_tft = ifelse(start_stop == "stop", timefromtransplant1, NA)) %>%
        dplyr::mutate(start = ifelse(start_stop == "start", ymd(date_lab), ymd(NA))) %>%
        dplyr::mutate(stop = ifelse(start_stop == "stop", ymd(date_lab), ymd(NA))) %>%
        dplyr::arrange(timefromtransplant1) %>%
        tidyr::fill(c(start, start_tft), .direction = "down") %>%
        tidyr::fill(c(stop, stop_tft), .direction = "up") %>%
        dplyr::mutate(across(c(start, stop), as.Date)) %>%
        dplyr::select(-c(start_stop, date_lab, timefromtransplant1)) %>%
        unique() %>%
        dplyr::mutate(diff = abs(as.numeric(
          difftime(start, stop, units = "days")
        ))) %>%
        dplyr::filter(diff >= 90)

      ckd15all <- dplyr::select(under15loc, pt_id, start_tft) %>%
        dplyr::mutate(ckd = 15)

    }


    if (length(egfr60stopstart$values) == 0) {
      under60loc <- dplyr::filter(egfr60stopstart, values > 0)
      dateprogression["pt_id", i] <- pt_id
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
      dateprogression["persontimedays_60", i] <- max(time$timefromtransplant1)
      dateprogression["sustained90day_60", i] <- 0
      ckd60all <- data.frame(pt_id = pt_id,
                             "start_tft" = NA,
                             "ckd" = 60)

    } else if (length(egfr60stopstart$values) > 0) {
      under60loc <- egfr60stopstart %>%
        dplyr::mutate(pt_id = ids[i]) %>%
        merge(time, all.x = T) %>%
        dplyr::select(c(pt_id, start_stop, date_lab, values, timefromtransplant1)) %>%
        dplyr::mutate(start_tft = ifelse(start_stop == "start", timefromtransplant1, NA)) %>%
        dplyr::mutate(stop_tft = ifelse(start_stop == "stop", timefromtransplant1, NA)) %>%
        dplyr::mutate(start = ifelse(start_stop == "start", ymd(date_lab), ymd(NA))) %>%
        dplyr::mutate(stop = ifelse(start_stop == "stop", ymd(date_lab), ymd(NA))) %>%
        dplyr::arrange(timefromtransplant1) %>%
        tidyr::fill(c(start, start_tft), .direction = "down") %>%
        tidyr::fill(c(stop, stop_tft), .direction = "up") %>%
        dplyr::mutate(across(c(start, stop), as.Date)) %>%
        dplyr::select(-c(start_stop, date_lab, timefromtransplant1)) %>%
        unique() %>%
        dplyr::mutate(diff = abs(as.numeric(
          difftime(start, stop, units = "days")
        ))) %>%
        dplyr::filter(diff >= 90)

      ckd60all <- dplyr::select(under60loc, pt_id, start_tft) %>%
        dplyr::mutate(ckd = 60)
    }

    #AKI HAPCA
    # if(nrow(akihapcaloc)==0){
    #   dateprogression["pt_id", i] <- pt_id
    #   dateprogression["akihapca_total_count", i] <- 0
    #   dateprogression["akihapcalonger7days_count", i] <- 0
    #   start_end_akihapcaloc_final<-data.frame(pt_id=ids[i],
    #                                           values=0,
    #                                           start_tft=NA)
    #
    #
    # }else if(nrow(akihapcaloc)>0){
    #   akihapca_akd<-akihapcaloc %>%
    #     summarise(n=nrow(.),nakdn=length(which(diff>7)))
    #
    #   dateprogression["pt_id", i] <- pt_id
    #   dateprogression["akihapca_total_count", i] <- akihapca_akd$n
    #   dateprogression["akihapcalonger7days_count", i] <- akihapca_akd$nakdn
    #
    #   start_end_akihapcaloc_final<-akihapcaloc
    #
    # }

    #AKI NHS
    if (nrow(akinhsloc) == 0) {
      dateprogression["pt_id", i] <- pt_id
      dateprogression["akinhs_total_count", i] <- 0
      dateprogression["akinhslonger7days_count", i] <- 0
      start_end_akinhs_final <- data.frame(pt_id = ids[i],
                                           values = 0,
                                           start_tft = NA)

    } else if (nrow(akinhsloc) > 0) {
      akinhs_akd <- akinhsloc %>%
        dplyr::summarise(n = nrow(.), nakdn = length(which(diff > 7)))

      dateprogression["pt_id", i] <- pt_id
      dateprogression["akinhs_total_count", i] <- akinhs_akd$n
      dateprogression["akinhslonger7days_count", i] <- akinhs_akd$nakdn

      start_end_akinhs_final <- akinhsloc
    }



    if (nrow(under45loc) == 0) {
      dateprogression["pt_id", i] <- pt_id
      dateprogression["persontimedays_45", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
      dateprogression["sustained90day_45", i] <- 0

    } else if (nrow(under45loc) > 0) {
      under45loc_sus <- under45loc %>%
        dplyr::filter(start_tft == min(start_tft))

      dateprogression["pt_id", i] <- pt_id
      dateprogression["persontimedays_45", i] <- under45loc_sus$start_tft
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["sustained90day_45", i] <- 1
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
    }



    if (nrow(under30loc) == 0) {
      dateprogression["pt_id", i] <- pt_id
      dateprogression["persontimedays_30", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
      dateprogression["sustained90day_30", i] <- 0

    } else if (nrow(under30loc) > 0) {
      under30loc_sus <- under30loc %>%
        dplyr::filter(start_tft == min(start_tft))

      dateprogression["pt_id", i] <- pt_id
      dateprogression["persontimedays_30", i] <- under30loc_sus$start_tft
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["sustained90day_30", i] <- 1
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
    }

    if (nrow(under15loc) == 0) {
      dateprogression["pt_id", i] <- pt_id
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
      dateprogression["persontimedays_15", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["sustained90day_15", i] <- 0

    } else if (nrow(under15loc) > 0) {
      under15loc_sus <- under15loc %>%
        dplyr::filter(start_tft == min(start_tft))

      dateprogression["pt_id", i] <- pt_id
      dateprogression["persontimedays_15", i] <- under15loc_sus$start_tft
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["sustained90day_15", i] <- 1
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
    }


    if (nrow(under60loc) == 0) {
      dateprogression["pt_id", i] <- pt_id
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
      dateprogression["persontimedays_60", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["sustained90day_60", i] <- 0

    } else if (nrow(under60loc) > 0) {
      under60loc_sus <- under60loc %>%
        dplyr::filter(start_tft == min(start_tft))

      dateprogression["pt_id", i] <- pt_id
      dateprogression["persontimedays_60", i] <- under60loc_sus$start_tft
      dateprogression["maxfollowuptime", i] <- max(time$timefromtransplant1, na.rm = T)
      dateprogression["sustained90day_60", i] <- 1
      dateprogression["last6months", i] <- last6months$mean6[1]
      dateprogression["last12months", i] <- last12months$mean12[1]
    }

    timeaki_tmerge[[i]] <- start_end_akinhs_final
    ckdstartstop[[i]] <- merge(ckd60all, ckd30all, all = T) %>%
      merge(ckd15all, all = T)

  }

  timeaki_tmerge_final <- dplyr::bind_rows(timeaki_tmerge[!sapply(timeaki_tmerge, is.null)]) %>%
    dplyr::select(pt_id, values, start_tft, stop_tft, diff)

  # all identified CKD start and stop times, to merge with AKI dataframe to exclude marked AKI events that actually were the begining of CKD
  ckdstartstop_final_all <- dplyr::bind_rows(ckdstartstop[!sapply(ckdstartstop, is.null)]) %>%
    dplyr::rename("start_tft_CKD" = "start_tft")

  ckdstartstop_final_year1 <- dplyr::bind_rows(ckdstartstop[!sapply(ckdstartstop, is.null)]) %>%
    dplyr::filter(start_tft <= 365 &
                    !is.na(start_tft) & start_tft > 0) %>%
    dplyr::rename("start_tft_CKD" = "start_tft")


  #need to remove flagged as this AKI was actually the start of an identified CKD episode for each stage of CKD
  #those left then need to make sure the AKI counted then are unique ie drop the ckd and flag columns


  ## outputs

  # allow as an output dataframe identifying each AKI event (1) for each id and the time from baseline they occured (event marker will be 0 if no AKIs occured)
  akiall <- timeaki_tmerge_final %>%
    dplyr::group_by(pt_id) %>%
    dplyr::arrange(start_tft, .by_group = T) %>%
    merge(ckdstartstop_final_all, all.x = T) %>%
    dplyr::mutate(flag = ifelse(start_tft == start_tft_CKD, 1, NA)) %>%
    dplyr::mutate(flag2 = ifelse(stop_tft == start_tft_CKD, 1, NA)) %>%
    dplyr::filter(is.na(flag) & is.na(flag2)) %>%
    dplyr::select(-start_tft_CKD, -ckd, -flag,-flag2) %>%
    unique()

  return(akiall)

  # allow as output - identify only those with AKI in the first year after tx and sum number of AKI in year 1
  # includes AKD events (ie. AKI>7 days)
  akiyear1 <- timeaki_tmerge_final %>%
    dplyr::group_by(pt_id) %>%
    dplyr::arrange(start_tft, .by_group = T) %>%
     dplyr::mutate(akiyear1 = ifelse(start_tft <= 365 &
                                       !is.na(start_tft), 1, NA)) %>%
    dplyr::filter(!is.na(akiyear1)) %>%
    merge(ckdstartstop_final_year1, all.x = T) %>%
    dplyr::mutate(flag = ifelse(start_tft == start_tft_CKD, 1, NA)) %>%
    dplyr::mutate(flag2 = ifelse(stop_tft == start_tft_CKD, 1, NA)) %>%
    dplyr::filter(is.na(flag) & is.na(flag2)) %>%
    dplyr::select(-start_tft_CKD, -ckd, -flag,-flag2) %>%
    unique() %>%
    dplyr::group_by(pt_id) %>%
    dplyr::summarise(akiyear1_sum = sum(akiyear1))

  return(akiyear1)

  # final output data frame of progression
  dateprogression_fin <- base::as.data.frame(base::t(dateprogression)) %>%
    dplyr::mutate(across(
      c(
        persontimedays_30,
        persontimedays_15,
        last6months,
        last12months
      ),
      as.numeric
    )) %>%
    dplyr::mutate(followupunder45 = ifelse(last6months < 45, 1, 0)) %>%
    dplyr::mutate(followupunder30 = ifelse(last6months < 30, 1, 0)) %>%
    dplyr::mutate(followupunder15 = ifelse(last6months < 15, 1, 0)) %>%
    dplyr::mutate(followupunder60 = ifelse(last6months < 60, 1, 0)) %>%
    dplyr::mutate(ckd45_progression = ifelse(followupunder45 == 1 &
                                               sustained90day_45 == 1, 1, 0)) %>%
    dplyr::mutate(ckd30_progression = ifelse(followupunder30 == 1 &
                                               sustained90day_30 == 1, 1, 0)) %>%
    dplyr::mutate(ckd15_progression = ifelse(followupunder15 == 1 &
                                               sustained90day_15 == 1, 1, 0)) %>%
    dplyr::mutate(ckd60_progression = ifelse(followupunder60 == 1 &
                                               sustained90day_60 == 1, 1, 0)) %>%
    dplyr::mutate(persontimedays_30_notadjusted = persontimedays_30) %>%
    dplyr::mutate(persontimedays_60_notadjusted = persontimedays_60) %>%
    dplyr::mutate(persontimedays_15_notadjusted = persontimedays_15) %>%
    dplyr::mutate(persontimedays_45_notadjusted = persontimedays_45) %>%
    dplyr::mutate(persontimedays_30 = ifelse(ckd30_progression != 1, maxfollowuptime, persontimedays_30)) %>%
    dplyr::mutate(persontimedays_60 = ifelse(ckd60_progression != 1, maxfollowuptime, persontimedays_60)) %>%
    dplyr::mutate(persontimedays_15 = ifelse(ckd15_progression != 1, maxfollowuptime, persontimedays_15)) %>%
    dplyr::mutate(persontimedays_45 = ifelse(ckd45_progression != 1, maxfollowuptime, persontimedays_45)) %>%
    select(pt_id,maxfollowuptime,contains("aki"),contains("last"),contains("followupunder"),contains("followup"),
           contains("sustained"),contains("progression"),contains("persontime"),everything())

  return(dateprogression_fin)

  # return numbers of creatinine results and the frequency of measurement (rate) in a word docx table
  numberofscrassessed %>%
    gtsummary::as_flex_table() %>%
    flextable::save_as_docx(paste0(outputdirectory,Sys.Date(),"_number_of_creatinine_results_assessed.docx"))


}
