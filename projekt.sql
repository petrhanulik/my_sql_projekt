
/* na tabulku covid_differences napojíme tabulku covid_tests,
zemì se jmenují rozdílnì v jednolivých tabulkách, proto použijeme, jako jednoznaèný klíè iso3 
z tabulky countries, nejprve napojím na covid_differences, tabulku countries, a pak covid_tests.
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

	
###################### SEKCE ÈASOVÝCH PROMÌNNÝCH ######################	
	
# pøidání sloupcù èasových promìnných - rozlišení víkendù, pracovnímu dni pøiøazuji 1, víkendu 0
# 									  - rozlišení roèních období 0 jako zima, 1 jako jaro, 2 léto, 3 podzim
	
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


###################### SEKCE SPECIFICKÝCH PROMÌNNÝCH ######################

/* z tabulky countries vytáhnu hustotu zalidnìní a medián vìku obyvatel a pøipojím ji na pøedešlý view
 * a vytvoøím jako tabulku t_peha_covid_description3
 */

create or replace view t_peha_covid_description3 as
select a.*, b.population_density, b.median_age_2018 
from t_peha_covid_description2 a
join countries b 
	on a.iso = b.iso3
	and b.population_density is not NULL 
	and b.median_age_2018 is not NULL 


/* v tomto kroku vytáhnu z tabulky economies HDP(2019), gini (za rok 2015 - dostatek údajù), dìtskou úmrtnost(2019), 
 * za rok 2015 gini údaj jen pro 80 zemí (ale více jak za pøedchozí roky) napojím na HDP a úmrnost
 * vytvoøím tabulku "t_peha_covid_HDP_GINI_MORT"
 * bohužel bude spoustu zemí po napojení chybìt
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


	
# spoèítám podíly jednotlivých náboženství jako procentní podíl pøíslušníkù náboženství na obyvatelstvu, beru rok 2020
# a vytvoøím tabulku "t_peha_covid_ration_religion"

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

	
	
# napojím na sebe oèekávanou dobu dožití v roce 1965 a v roce 2015 a spoèítám jejich rozdíl
# èím vìtší záporné èíslo tím rychlejší rozvoj probìhl
# uložím jako view  "v_peha_covid_expectancy_difference"	
	
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
	
	
/* v tomto kroku propojím následující pohledy:
 * 	- v_peha_covid_HDP_GINI_MORT,
 *  - v_peha_covid_ration_religion,
 *  - v_peha_covid_expectancy_difference.
 * a tyto následnì uložím do nového pohledu jako "v_peha_covid_specificke"
 */	

create or replace table t_peha_covid_specificke as 
select a.*, b.religion, b.adherents, c.expectancy_difference
from t_peha_covid_HDP_GINI_MORT a 
join t_peha_covid_ration_religion b
	on a.country = b.country 
join t_peha_covid_expectancy_difference c 
	on a.iso3 = c.iso3	
	

# nyní spojím pohled "v_peha_covid_description3" s pohledem "v_peha_covid_specificke" tím mám spojené èasové promìnné 
# s promìnnými specifickými pro daný stát

create or replace table t_peha_casove_specificke as 
select a.*, b.GDP_pc, b.mortaliy_under5, b.gini, b.iso3, b.religion, b.adherents, b.expectancy_difference
from t_peha_covid_description3 a
join t_peha_covid_specificke b
	on a.iso = b.iso3


------------------------------------

###################### SEKCE VÌNOVANÁ POÈASÍ ######################


/* vytvoøíme tabulku "t_peha_avg_temp" s prùmìrnou denní teplotou,
 * pokud provedeme select distinct city zjistíme, že máme záznam jen pro 35 mìst,
 * tabulka coutries obsahuje sloupec capital_city, použijemeho pro napojení, jenže z 34 mìst(Brno nebereme)
 * nedojde k napojení u 11 protože se jmenují jinak v tabulce weather a jinak v tabulce mojí s prùmìrnou denní teplotou:
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


/* pøedešlý problém je chybou nekonzistetní databáze, lze øešit pøejmenováním hlavních mìst,
 * tak aby se jmenovala stejnì v tabulce weather a tabulce countries,
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
	

aby došlo k napojení pøes všechna hlavní mìsta.
Ale vytvoøi takovou tabulku mi nejde - èasovì nároèné, stále nereaguje.... Vytvoøím-li pohled, pak operace nad pohledem probíhají i pøes 15 minut 
a stále se nic nedìje.
 */


# pøipojím tedy prùmìrnou teplotu jen k tìm mìstù, která mám

select w.city, w.date,  c.country, c.iso3, w.avg_temp_day
from t_peha_avg_temp w
left join countries c 
	on w.city = c.capital_city 
 

# zjednodušenì poèítám kolik mohlo být deštivých hodin bìhem dne, protože mám záznamy jen po tøech hodinách
# neberu mezihodiny v potaz

select city, date,
case when rain > 0 then 1 else 0 end as rainy_day,
sum(case when rain > 0 then 1 else 0 end) as rainy_hours
from weather w	
group by city, date
	
	
# vyberu maximální vítr v daném dni

select city, date, max(wind) as max_wind
from weather w 
group by city, date
	

# v tomto kroku propojim všechny informace, které mám o poèasí

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




################ SPOJÍM VŠECHNY ÚDAJE DO JEDNÉ TABULKY ###############

create table t_petr_hanulik_projekt_SQL_final
select a.*, b.avg_temp_day, b.rainy_hours, b.max_wind
from t_peha_casove_specificke a 
join t_peha_weahter_description b
	on a.iso3 = b.iso3
	and a.date = b.date







