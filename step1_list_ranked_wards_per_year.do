// This code calculates the most common ward, given first three characters of ICD10 diagnosis code 
use "data",clear

gen ICD10_cat3 = substr(ICD10_main_diagnosis,1,3)
gen year       = string(IN,"%tcCCYY")
by hospital year ward_id ICD10_cat3, sort: gen freq = _N
by hospital year ward_id ICD10_cat3, sort: keep if _n==1

// Rank wards per hospital
gsort hospital year ICD10_cat3 -freq
by hospital year ICD10_cat3, sort: gen rank = _n
keep hospital year ICD10_cat3 freq ward_id rank

// Remove outlier wards
egen N = sum(freq), by(hospital year ICD10_cat3)
gen ratio = freq/N
keep if ratio>1/10

// List wards per hosptial with rank and proportion of patients
rename ward_id ward_rank 
reshape wide ward_rank ratio freq N, i(hospital ICD10_cat3 year) j(rank)
sort hospital year ICD10_cat3

// Save file for later
save "ranked_hospital_wards_per_year", replace 



