
// This code calculates occupancy at all relevant wards at all relevant hour points
foreach hour of numlist 0 8 12 16 {
	use "data",clear

	// Generate virtual patients, for which data is calculated
	replace IN  = .
	gen virtual = 1

	sum in_date
	local mindate = r(min)
	local maxdate = r(max)
	local n_dates = `maxdate' - `mindate' + 180

	sort hospital ward_id
	by hospital ward_id: keep if _n == 1
	replace in_date = `mindate' - 60
	expand `n_dates'

	
	sort hospital ward_id
	replace in_date = in_date[_n-1]+1 if hospital == hospital[_n-1] & ward_id == ward_id[_n-1]
	replace IN  = mdyhms(month(in_date), day(in_date), year(in_date),`hour',0,0)

	// Now there is one line per ward, per date, with a given hour of the day
	
	// Add the actual admissions to the virtual
	append using "data"
	
	// Tag stroke, MI and HF - patients. Each line is an admission that may be part of an episode.
	// Episodes are identified by hospitalisation_id
	gen str = 0
	gen mi  = 0
	gen hf = 0
	foreach var of varlist tilstand*{
		replace str = 1 if inlist(substr(`var',1,3),"I61","I63","I64") 
		replace mi  = 1 if inlist(substr(`var',1,3),"I21","I22") 
		replace hf = 1 if inlist(substr(`var',1,3),"I50") 
	}
	egen STR  = max(str), by(hospitalisation_id)
	egen MI   = max(mi), by(hospitalisation_id)
	egen HF  = max(hf), by(hospitalisation_id)

	keep virtual in_date IN OUT hospital ward_id STR MI HF

	local maxlos = 1000*60*60*24*90

	// Initialise variables for calculating occupancy
	sort hospital ward_id IN OUT
	local continue    = 1
	local i           = 0
	gen X             = 0	
	gen occupancy     = 0
	gen occupancy_STR = 0
	gen occupancy_MI  = 0
	gen occupancy_HF  = 0

	// Calculating occupancy
	while `continue' {
		local i = `i'+1
		drop X
		by hospital ward_id: gen X = (OUT[_n-`i'] > IN) & (virtual[_n-`i']!=1) & (OUT[_n-`i']!=.) & (IN-IN[_n-`i']<`maxlos')
		replace occupancy     = occupancy   + X
		replace occupancy_STR = occupancy_STR + X*STR[_n-`i']
		replace occupancy_MI  = occupancy_MI  + X*MI[_n-`i']
		replace occupancy_HF  = occupancy_HF  + X*HF[_n-`i']

		di `i'
		drop X
		by hospital ward_id: gen X = (IN-IN[_n-`i']<`maxlos')
		count if X
		local continue = r(N)
	}	
	drop X

	keep if virtual == 1
	drop virtual OUT IN
	gen hour = `hour'

	// Code for calculating Norwegian holidays
	gen holiday = inlist(string(in_date,"%tdNN-DD"), "05-01", "12-24", "12-25", "12-26", "01-01", "05-17")
	local palmesondager mdy(4,9,2006) mdy(4,1,2007) mdy(3,16,2008) mdy(4,5,2009) mdy(3,28,2010) mdy(4,17,2011) mdy(4,1,2012) mdy(3,24,2013) mdy(4,13,2014) mdy(3,29,2015) mdy(3,20,2016) mdy(4,9,2017) mdy(3,25,2018) mdy(4,14,2019) mdy(4,5,2020)
	foreach palmesondag of local palmesondager{
		foreach k of numlist 4 5 6 7 8 46 56 57{
			replace holiday = 1 if in_date == `palmesondag' + `k'
		}
	}
	
	
	// Additional variables with aggregated statistics
	gen year    = year(in_date)
	gen month   = month(in_date)
	gen dow     = dow(in_date)
	gen weekend = dow==0|dow==6|holiday==1
	gen month3  = floor((month-1)/3) 

	gen dow_holiday_inn     = dow
	replace dow_holiday_inn = 6 if holiday

	egen id_month_dow   = group(hospital ward_id year month weekend)
	egen mean_occupancy_hour`hour'       = mean(occupancy), by(id_month_dow)
	egen sd_occupancy_hour`hour'         = sd(occupancy),   by(id_month_dow)
	
	keep hospital ward_id in_date occupancy* hour mean_* sd_*
		
	save "Occupancy_hour`hour'", replace
}


