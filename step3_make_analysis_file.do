cls
use "data",clear

gen month   = month(in_date)
gen hour    = hh(IN)
gen weekend = dow(IN)==0|dow(IN)==6
gen year    = string(IN,"%tcCCYY")

// Code for calculating Norwegian holidays
gen holiday = inlist(string(in_date,"%tdNN-DD"), "05-01", "12-24", "12-25", "12-26", "01-01", "05-17")
local palmesondays mdy(4,9,2006) mdy(4,1,2007) mdy(3,16,2008) mdy(4,5,2009) mdy(3,28,2010) mdy(4,17,2011) mdy(4,1,2012) mdy(3,24,2013) mdy(4,13,2014) mdy(3,29,2015) mdy(3,20,2016) mdy(4,9,2017) mdy(3,25,2018) mdy(4,14,2019) mdy(4,5,2020)
foreach palmesondag of local palmesondays{
	foreach k of numlist 4 5 6 7 8 46 56 57{
		replace holiday = 1 if in_date == `palmesondag' + `k'
	}
}


// Tag first stay in episode
sort hospitalisation_id IN OUT 
by hospitalisation_id: gen ifnr = _n

// Tag index hospitalisations
gen ICD10_cat3 = substr(ICD10_main_diagnosis,1,3)
gen str = ICD10_cat3 == "I61" | ICD10_cat3 == "I63" | ICD10_cat3 == "I64" 
gen mi  = ICD10_cat3 == "I21" | ICD10_cat3 == "I22"
gen hf  = ICD10_cat3 == "I50"
egen STR = max(str), by(hospitalisation_id)
egen MI  = max(mi), by(hospitalisation_id)
egen HF  = max(hf), by(hospitalisation_id)
gen index = STR|MI|HF


// Calculate length of stay from hospitalisation
egen IN_episode       = min(IN), by(hospitalisation_id)
egen OUT_episode      = max(OUT),  by(hospitalisation_id)
egen in_date_episode  = min(in_date),  by(hospitalisation_id)
egen out_date_episode = max(out_date),  by(hospitalisation_id)
replace in_date       = in_date_episode
replace out_date      = out_date_episode
gen LOS = out_date - in_date


//
// Keep only index patients
//
egen keep    = max(index), by(popid)
keep if keep 
drop keep*

// Categorise main diagnosis. If several diagnoses, categorise by first
foreach var of varlist str mi hf{
	replace `var' = ifnr if `var'
	replace `var' = . if `var' == 0
	egen first_`var' = min(`var'), by(hospitalisation_id)
}
gen diagnosis_group = 0
replace diagnosis_group = 1 if first_str!=.
replace diagnosis_group = 2 if first_mi!=.
replace diagnosis_group = 1 if first_str < first_mi
replace diagnosis_group = 3 if first_hf!=.
replace diagnosis_group = 1 if first_str < first_hf
replace diagnosis_group = 2 if first_mi  < first_hf



//
// Keep one line per patient per episode
//
keep if ifnr == 1
drop ifnr

// Generate variables tracking hospitalisations before and after
sort popid IN
gen last_admission = in_date-out_date[_n-1]  if popid==popid[_n-1]
gen next_admission = in_date[_n+1]           if popid==popid[_n+1]

foreach days of numlist 30 60 90 180 365 {
	gen LOS_within`days'd    = 0
	gen LOSdays_within`days'd = 0
}

sort popid IN
local continue = 1
local i        = 1
while `continue' {
	foreach days of numlist 30 60 90 180 365{
		by popid: gen X = IN[_n+`i'] - IN   < msofhours(24*`days')
		by popid: gen Y = OUT[_n+`i']  - IN > msofhours(24*`days')
	
		replace LOS_within`days'd  = LOS_within`days'd + LOS[_n+`i'] if X==1
		replace LOS_within`days'd  = LOS_within`days'd - (OUT[_n+`i']-(IN+msofhours(24*`days')))/1000/60/60/24 if Y==1&X==1
	
		drop X Y
		
		by popid: gen inX = in_date[_n+`i']
		by popid: gen outX  =  out_date[_n+`i']
		replace utX                    = in_date + `days'-1 if utX > in_date + `days'-1
		gen LOSX                       = outX - inX + 1
		replace LOSX                   = 0 if LOSX==. | LOSX <0
		replace LOSdays_within`days'd  = LOSdays_within`days'd + LOSX

		drop inX outX LOSX
	}
	by popid: gen X = IN[_n+`i']-IN < msofhours(24*360)
	count if X
	local continue = r(N)
	drop X
	local i = `i'+1
}



//
// Keep only index admissions
//
keep if index
drop index

// Compute GP use
foreach dt of numlist 30 60 90 180 365{
	gen GPcontacts_post`dt' = 0
	gen GPcontacts_pre`dt'  = 0
}

foreach year of numlist 2006/2018 {
	preserve
	use "GP_use_year`year'", clear
	sort popid date
	by popid dato: gen keep = _n==1
	keep if keep
	keep popid dato
	save "temp", replace
	restore
	
	joinby popid using "temp", unmatched(master)
	gen days_from_in  = date-in_date
	
	sort popid IN
	by popid IN: gen keep  = _n==1
	foreach dt of numlist 30 60 90 180 365{
		gen post = (days_from_in>0)&(days_from_in<= `dt')
		gen pre  = (days_from_in<0)&(days_from_in>=-`dt')
		egen N_contacts_post  = sum(post), by(popid IN)
		egen N_contacts_pre   = sum(pre),  by(popid IN)
			
		replace GPcontacts_post`dt' = GPcontacts_post`dt' + N_contacts_post
		replace GPcontacts_pre`dt'  = GPcontacts_pre`dt'  + N_contacts_pre
			
		drop post pre N_contacts*
	}
	keep if keep ==1
	drop days_from_in date keep _merge 
}
		


		


// Get top ranked ward for diagnosis
destring year, replace
merge m:1 hospital year ICD10_cat3 using "ranked_hospital_wards_per_year", keepusing(ward_rank1)
keep if _merge == 3
drop _merge

// Add occupancy at the top ranked ward
foreach hour of numlist 0 8 16{
	preserve
	use "Occupancy_hour`hour'", clear
	
	rename ward_id ward_rank1
	rename occupancy occupancy`hour'
	rename occupancy_STR occupancy_STR_hour`hour'
	rename occupancy_MI  occupancy_MI_hour`hour'
	rename occupancy_HF  occupancy_HF_hour`hour'
	keep hospital in_date occupancy* mean* sd* ward_rank1
	
	save "temp", replace
	restore
	merge m:1 in_date hospital ward_rank1 using "temp"
	drop if _merge ==2
	drop _merge
}


save "analysis_file", replace 






