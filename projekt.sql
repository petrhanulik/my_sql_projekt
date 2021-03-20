
/* na tabulku covid_differences napoj�me tabulku covid_tests,
zem� se jmenuj� rozd�ln� v jednoliv�ch tabulk�ch, proto pou�ijeme, jako jednozna�n� kl�� iso3 
z tabulky countries, nejprve napoj�m na covid_differences, tabulku countries, a pak covid_tests.
*/

create table t_peha_covid_description as
select a.country, a.date, a.confirmed, c.tests_performed, b.population , c.ISO
from covid19_basic_differences a
join lookup_table b 
	on a.country = b.country
	and province is null
join covid19_tests c 
	on a.date = c.date 
	and b.iso3 = c.ISO 

	
###################### SEKCE �ASOV�CH PROM�NN�CH ######################	
	
# p�id�n� sloupc� �asov�ch prom�nn�ch - rozli�en� v�kend�, pracovn�mu dni p�i�azuji 1, v�kendu 0
# 									  - rozli�en� ro�n�ch obdob� 0 jako zima, 1 jako jaro, 2 l�to, 3 podzim
	
create or replace table t_peha_covid_description2 as
select a.*, 
	(case when weekday(a.date) in (5,6) then 0 else 1 end) as weekend,	
	case when a.date between '2020-02-25' and '2020-03-19' then 0
		 when a.date between '2020-03-20' and '2020-06-19' then 1
		 when a.date between '2020-06-20' and '2020-09-20' then 2
		 else 3
		 end as season
from(
select*
from t_peha_covid_description 
) a


###################### SEKCE SPECIFICK�CH PROM�NN�CH ######################

/* z tabulky countries vyt�hnu hustotu zalidn�n� a medi�n v�ku obyvatel a p�ipoj�m ji na p�ede�l� view
 * a vytvo��m jako tabulku t_peha_covid_description3
 */

create or replace view t_peha_covid_description3 as
select a.*, b.population_density, b.median_age_2018 
from t_peha_covid_description2 a
join countries b 
	on a.iso = b.iso3
	and b.population_density is not NULL 
	and b.median_age_2018 is not NULL 


/* v tomto kroku vyt�hnu z tabulky economies HDP(2019), gini (za rok 2015 - dostatek �daj�), d�tskou �mrtnost(2019), 
 * za rok 2015 gini �daj jen pro 80 zem� (ale v�ce jak za p�edchoz� roky) napoj�m na HDP a �mrnost
 * vytvo��m tabulku "t_peha_covid_HDP_GINI_MORT"
 * bohu�el bude spoustu zem� po napojen� chyb�t
*/

create or replace table t_peha_covid_HDP_GINI_MORT as 
select a.*, b.gini, c.iso3 
from (
	select country,
		round(GDP/population*100,2) as GDP_pc, mortaliy_under5 
	from economies e 
	where year = 2019
	) a
join (	
	select country,gini
	from economies e 
	where year = 2015 and gini is not null
	) b
on a.country = b.country
join countries c 
	on a.country = c.country


	
# spo��t�m pod�ly jednotliv�ch n�bo�enstv� jako procentn� pod�l p��slu�n�k� n�bo�enstv� na obyvatelstvu, beru rok 2020
# a vytvo��m tabulku "t_peha_covid_ration_religion"

create or replace table t_peha_covid_ration_religion as
select b.country, b.religion,
	round(b.population/a.pop_total*100,2) as adherents
from (
	select country, sum(population) as pop_total
	from religions r 
	where year = 2020 
	group by country
	) a
join religions b
	on a.country = b.country 
	and b.population !=0
	and b.year = 2020

	
	
# napoj�m na sebe o�ek�vanou dobu do�it� v roce 1965 a v roce 2015 a spo��t�m jejich rozd�l
# ��m v�t�� z�porn� ��slo t�m rychlej�� rozvoj prob�hl
# ulo��m jako view  "v_peha_covid_expectancy_difference"	
	
create or replace table t_peha_covid_expectancy_difference as 
select a.country, a.iso3,
	round((a.life_expectancy - b.life_expectancy),2) as  expectancy_difference
from(
	select country, life_expectancy, iso3 
	from life_expectancy le 
	where year = 1965
	) a
join(
select country, life_expectancy, iso3 
from life_expectancy le 
where year = 2015	
	) b
on a.iso3 = b.iso3	
	
	
/* v tomto kroku propoj�m n�sleduj�c� pohledy:
 * 	- v_peha_covid_HDP_GINI_MORT,
 *  - v_peha_covid_ration_religion,
 *  - v_peha_covid_expectancy_difference.
 * a tyto n�sledn� ulo��m do nov�ho pohledu jako "v_peha_covid_specificke"
 */	

create or replace table t_peha_covid_specificke as 
select a.*, b.religion, b.adherents, c.expectancy_difference
from t_peha_covid_HDP_GINI_MORT a 
join t_peha_covid_ration_religion b
	on a.country = b.country 
join t_peha_covid_expectancy_difference c 
	on a.iso3 = c.iso3	
	

# nyn� spoj�m pohled "v_peha_covid_description3" s pohledem "v_peha_covid_specificke" t�m m�m spojen� �asov� prom�nn� 
# s prom�nn�mi specifick�mi pro dan� st�t

create or replace table t_peha_casove_specificke as 
select a.*, b.GDP_pc, b.mortaliy_under5, b.gini, b.iso3, b.religion, b.adherents, b.expectancy_difference
from t_peha_covid_description3 a
join t_peha_covid_specificke b
	on a.iso = b.iso3


------------------------------------

###################### SEKCE V�NOVAN� PO�AS� ######################


/* vytvo��me tabulku "t_peha_avg_temp" s pr�m�rnou denn� teplotou,
 * pokud provedeme select distinct city zjist�me, �e m�me z�znam jen pro 35 m�st,
 * tabulka coutries obsahuje sloupec capital_city, pou�ijemeho pro napojen�, jen�e z 34 m�st(Brno nebereme)
 * nedojde k napojen� u 11 proto�e se jmenuj� jinak v tabulce weather a jinak v tabulce moj� s pr�m�rnou denn� teplotou:
 * 
 * select DISTINCT w.city, c.capital_city 
from weather w
left join countries c 
	on w.city = c.capital_city 
where c.capital_city is NULL 

*/


create table t_peha_avg_temp
select city, date, round(avg(temp),2) as avg_temp_day
from weather w 
where hour in (0,3,6,9,12,15,18)
group by city, date


/* p�ede�l� probl�m je chybou nekonzistetn� datab�ze, lze �e�it p�ejmenov�n�m hlavn�ch m�st,
 * tak aby se jmenovala stejn� v tabulce weather a tabulce countries,
 * 
 * create or replace view v_peha_we_changed as 
select w2.*,
	case when w.city = 'Prague' then 'Praha'  
	 	 when w.city = 'Vienna' then 'Vien' 
	 	 when w.city = 'Warsaw' then 'Warszawa '
	 	 when w.city = 'Roma' then 'Rome'
	 	 when w.city = 'Brussels' then 'Bruxelles [Brussels]'
	 	 when w.city = 'Luxembourg' then 'Luxembourg [Luxemburg/L]'
	 	 when w.city = 'Lisbon' then 'Lisboa'
	 	 when w.city = 'Helsinky' then 'Helsinki [Helsingfors]'
	 	 when w.city = 'Athens' then 'Athenai'
	 	 when w.city = 'Bucharest' then 'Budapest'
	 	 when w.city = 'Kiev' then 'Kyiv'	 
	 else w.city
	end as city_overwritten
from weather w
join weather w2 
	on w.city = w2.city
	

aby do�lo k napojen� p�es v�echna hlavn� m�sta.
Ale vytvo�i takovou tabulku mi nejde - �asov� n�ro�n�, st�le nereaguje.... Vytvo��m-li pohled, pak operace nad pohledem prob�haj� i p�es 15 minut 
a st�le se nic ned�je.
 */


# p�ipoj�m tedy pr�m�rnou teplotu jen k t�m m�st�, kter� m�m

select w.city, w.date,  c.country, c.iso3, w.avg_temp_day
from t_peha_avg_temp w
left join countries c 
	on w.city = c.capital_city 
 

# zjednodu�en� po��t�m kolik mohlo b�t de�tiv�ch hodin b�hem dne, proto�e m�m z�znamy jen po t�ech hodin�ch
# neberu mezihodiny v potaz

select city, date,
case when rain > 0 then 1 else 0 end as rainy_day,
sum(case when rain > 0 then 1 else 0 end) as rainy_hours
from weather w	
group by city, date
	
	
# vyberu maxim�ln� v�tr v dan�m dni

select city, date, max(wind) as max_wind
from weather w 
group by city, date
	

# v tomto kroku propojim v�echny informace, kter� m�m o po�as�

create or replace table t_peha_weahter_description
select w.city, w.date,  c.country, c.iso3, w.avg_temp_day, r.rainy_hours, wi.max_wind
from t_peha_avg_temp w
left join countries c 
	on w.city = c.capital_city 
join (
	select city, date,
	case when rain > 0 then 1 else 0 end as rainy_day,
	sum(case when rain > 0 then 1 else 0 end) as rainy_hours
	from weather w	
	group by city, date
	) r
on w.city = r.city
and w.date = r.date
join (
	select city, date, max(wind) as max_wind
	from weather w 
	group by city, date
	) wi
on w.city = wi.city
and w.date = wi.date


select*
from t_peha_weahter_description




################ SPOJ�M V�ECHNY �DAJE DO JEDN� TABULKY ###############

create table t_petr_hanulik_projekt_SQL_final
select a.*, b.avg_temp_day, b.rainy_hours, b.max_wind
from t_peha_casove_specificke a 
join t_peha_weahter_description b
	on a.iso3 = b.iso3
	and a.date = b.date







