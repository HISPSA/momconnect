
CREATE OR REPLACE FUNCTION momconnect_aggregate_all_before_today_parmDays(IN days integer)
  RETURNS TABLE(datetime timestamp without time zone, operation character varying, rowcount bigint) AS
$BODY$

truncate table _momc_log;
truncate table _momc_tally;

/* SCRIPT 1: REGISTRATIONS AND SUBSCRIPTIONS */
 
/* Load ProgramStages ("Clinic Registration", "CHW Identification", "Public Subscription") per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,uid2,period,value,storedby,created)
SELECT "A".organisationunitid, "A".UID1, "A".UID2, dtmEvent, RecordCount, 'aggregated_from_MomScript',CURRENT_DATE FROM (
	SELECT 
	  programstageinstance.organisationunitid,
	  '' as UID1, 
	  programstage.uid as UID2, 
	  programstage.name, 
	  to_char(programstageinstance.executiondate, 'yyyymmdd') as dtmEvent,
	  programstageinstance.executiondate,
	  COUNT(programstageinstance.*) as RecordCount  
	FROM 
	  public.programinstance, 
	  public.programstageinstance,
	  public.programstage
	WHERE 
	  programstage.programstageid = programstageinstance.programstageid AND
	  programstageinstance.programinstanceid = programinstance.programinstanceid AND programstageinstance.programstageid In (47888,47887,47886) AND 
	  programstageinstance.executiondate >= CURRENT_DATE - days AND programstageinstance.executiondate < CURRENT_DATE
	GROUP BY 
	  programstageinstance.organisationunitid,
	  programstage.uid, 
	  programstage.name, 
	  to_char(programstageinstance.executiondate, 'yyyymmdd'),
	  programstageinstance.executiondate
) as "A" 
WHERE "A".executiondate >= CURRENT_DATE - days AND "A".executiondate < CURRENT_DATE;


UPDATE _momc_tally "A" SET Found = 0;
UPDATE _momc_tally "A" SET periodid = "B".periodid FROM  period "B" WHERE "A".period = to_char("B".startdate, 'yyyymmdd') AND "B".periodtypeid = 1;

/* MAP "Client Registrations inside Facility" to "Clinic Registration" */
UPDATE _momc_tally "A" SET deuid = 'lPVvmrINVHS', dataelementid = 7253258 WHERE "A".UID2 = 'YlHchjzriaH';
/* MAP "Client Subscribers Identified by a CHW" to "CHW Identification" */
UPDATE _momc_tally "A" SET deuid = 'hll1AMnqnro', dataelementid = 7253250 WHERE "A".UID2 = 'PzR6dRKsGZQ';
/* MAP "Client Subscribers Self Subscribing" to "Public Subscription" */
UPDATE _momc_tally "A" SET deuid = 'DHP3S3oR8Ob', dataelementid = 7253242 WHERE "A".UID2 = 'AVSoW6NZOCD';
/* Flag records already present in DataValues (to avoid errors appending Unique-Index-Violations) */
UPDATE _momc_tally "A" SET found = 1 FROM datavalue "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "B".sourceid = "A".organisationunitid;

/* Update datavalue from temp where values are different */
UPDATE datavalue "A" SET value = "B".value FROM _momc_tally "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "A".sourceid = "B".organisationunitid AND "B".Found <> 0 AND "A".value <> "B".value;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Clinic Registration (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7253258;
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Subscriptions (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7253250;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Subscriptions (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7253242;

/* Append New data values */
INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated, followup)
SELECT "A".dataelementid, "A".periodid, "A".organisationunitid, 16, 16, "A".value, "A".storedby, "A".created, "A".lastupdated, FALSE FROM _momc_tally "A" WHERE "A".found <> 1;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Clinic Registration (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7253258;
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Subscriptions (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7253250;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Subscriptions (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7253242;


/* SCRIPT 2: REGISTRATIONS CONVERTED FROM SUBSCRIPTIONS */

truncate table _momc_tally;

/* CREATE Registrations converted from CHW Identifications */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT 
  "REG".organisationunitid, "REG".organisationunitid, 'F5Q88S4biV3', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "CHW", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "CHW".programinstanceid AND
  "CHW".programstageid = 47887 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 



/* CREATE Registrations converted from PUBLIC Subscriptions */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT 
  "REG".organisationunitid, "REG".organisationunitid, 'ML6rEaBympC', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "CHW", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "CHW".programinstanceid AND
  "CHW".programstageid = 47886 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 


/* CHW Identified Registrations (Converted) within 1 Month */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT 
  "REG".organisationunitid, "REG".organisationunitid, 'kVuIug0bDcZ', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "CHW", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "CHW".programinstanceid AND
  "CHW".programstageid = 47887 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE AND
  EXTRACT(year FROM age("REG".executiondate,"CHW".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"CHW".executiondate)) < 1
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 


/* CHW Identified Registrations (Converted) within 1 - 2 Months */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT 
  "REG".organisationunitid, "REG".organisationunitid, 'TkNTN1Di74F', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "CHW", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "CHW".programinstanceid AND
  "CHW".programstageid = 47887 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE AND
  EXTRACT(year FROM age("REG".executiondate,"CHW".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"CHW".executiondate)) >= 1 AND
  EXTRACT(year FROM age("REG".executiondate,"CHW".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"CHW".executiondate)) < 2  
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 


/* CHW Identified Registrations (Converted) within 2 - 3 Months */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT 
  "REG".organisationunitid, "REG".organisationunitid, 'elDuId82Ech', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "CHW", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "CHW".programinstanceid AND
  "CHW".programstageid = 47887 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE AND
  EXTRACT(year FROM age("REG".executiondate,"CHW".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"CHW".executiondate)) >= 2 AND
  EXTRACT(year FROM age("REG".executiondate,"CHW".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"CHW".executiondate)) < 3  
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 


/* CHW Identified Registrations (Converted) AFTER 3 Months */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT 
  "REG".organisationunitid, "REG".organisationunitid, 'dwqkOMJkDhC', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "CHW", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "CHW".programinstanceid AND
  "CHW".programstageid = 47887 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE AND
  EXTRACT(year FROM age("REG".executiondate,"CHW".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"CHW".executiondate)) >= 3
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 

/* Public-Subscribed Registrations (Converted) within 1 Month */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT 
  "REG".organisationunitid, "REG".organisationunitid, 'orDTdGUMTR4', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "SUB", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "SUB".programinstanceid AND
  "SUB".programstageid = 47886 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE AND
  EXTRACT(year FROM age("REG".executiondate,"SUB".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"SUB".executiondate)) < 1
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 


/* Public-Subscribed Registrations (Converted) within 1 - 2 Months */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT
  "REG".organisationunitid, "REG".organisationunitid, 'b1zV5iZXXlo', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "SUB", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "SUB".programinstanceid AND
  "SUB".programstageid = 47886 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE AND
  EXTRACT(year FROM age("REG".executiondate,"SUB".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"SUB".executiondate)) >= 1 AND
  EXTRACT(year FROM age("REG".executiondate,"SUB".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"SUB".executiondate)) < 2
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 


/* Public-Subscribed Registrations (Converted) within 2 - 3 Months */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT
  "REG".organisationunitid, "REG".organisationunitid, 'vqwlped2JGq', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "SUB", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "SUB".programinstanceid AND
  "SUB".programstageid = 47886 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE AND
  EXTRACT(year FROM age("REG".executiondate,"SUB".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"SUB".executiondate)) >= 2 AND
  EXTRACT(year FROM age("REG".executiondate,"SUB".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"SUB".executiondate)) < 3
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 


/* Public-Subscribed Registrations (Converted) AFTER 3 Months */
INSERT INTO _momc_tally (organisationunitid,ouuid,deuid,period,value,storedby,created)
SELECT
  "REG".organisationunitid, "REG".organisationunitid, 'fGwLFzuAQcS', to_char("REG".executiondate, 'yyyymmdd') as dtmEvent, Count(*) as Converted, 'aggregated_from_MomScript',CURRENT_DATE
FROM 
  public.programstageinstance "SUB", 
  public.programstageinstance "REG", 
  public.programinstance "momC"
WHERE 
  "REG".programinstanceid = "momC".programinstanceid AND
  "momC".programinstanceid = "SUB".programinstanceid AND
  "SUB".programstageid = 47886 AND 
  "REG".programstageid = 47888 AND "REG".executiondate >= CURRENT_DATE - days AND "REG".executiondate < CURRENT_DATE AND
  EXTRACT(year FROM age("REG".executiondate,"SUB".executiondate))*12 + EXTRACT(month FROM age("REG".executiondate,"SUB".executiondate)) >= 3
GROUP BY "REG".organisationunitid,"REG".organisationunitid, to_char("REG".executiondate, 'yyyymmdd'); 


UPDATE _momc_tally "A" SET Found = 0;
UPDATE _momc_tally "A" SET periodid = "B".periodid FROM  period "B" WHERE "A".period = to_char("B".startdate, 'yyyymmdd') AND "B".periodtypeid = 1;
UPDATE _momc_tally "A" SET dataelementid = "B".dataelementid FROM  dataelement "B" WHERE "A".deuid = "B".uid;
UPDATE _momc_tally "A" SET found = 1 FROM datavalue "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "B".sourceid = "A".organisationunitid;

/* Update datavalue from temp where values are different */
UPDATE datavalue "A" SET value = "B".value FROM _momc_tally "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "A".sourceid = "B".organisationunitid AND "B".Found <> 0 AND "A".value <> "B".value;

insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'F5Q88S4biV3';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'ML6rEaBympC';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (updates) BEFORE 1 Month', Count(*) from  _momc_tally where found <> 0 AND deuid = 'kVuIug0bDcZ';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (updates) 1 - 2 Months', Count(*) from  _momc_tally where found <> 0 AND deuid = 'TkNTN1Di74F';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (updates) 2 - 3 Months', Count(*) from  _momc_tally where found <> 0 AND deuid = 'elDuId82Ech';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (updates) BEFORE 1 Months', Count(*) from  _momc_tally where found <> 0 AND deuid = 'orDTdGUMTR4';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (updates) 1 - 2 Months', Count(*) from  _momc_tally where found <> 0 AND deuid = 'b1zV5iZXXlo';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (updates) 2 - 3 Months', Count(*) from  _momc_tally where found <> 0 AND deuid = 'vqwlped2JGq';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (updates) AFTER 3 Months', Count(*) from  _momc_tally where found <> 0 AND deuid = 'dwqkOMJkDhC';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (updates) AFTER 3 Months', Count(*) from  _momc_tally where found <> 0 AND deuid = 'dwqkOMJkDhC';

/* Append New data values */
INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated, followup)
SELECT "A".dataelementid, "A".periodid, "A".organisationunitid, 16, 16, "A".value, "A".storedby, "A".created, "A".lastupdated, FALSE FROM _momc_tally "A" WHERE "A".found <> 1;


insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'F5Q88S4biV3';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'ML6rEaBympC';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (new) BEFORE 1 Month', Count(*) from  _momc_tally where found = 0 AND deuid = 'kVuIug0bDcZ';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (new) 1 - 2 Months', Count(*) from  _momc_tally where found = 0 AND deuid = 'TkNTN1Di74F';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (new) 2 - 3 Months', Count(*) from  _momc_tally where found = 0 AND deuid = 'elDuId82Ech';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (new) BEFORE 1 Month', Count(*) from  _momc_tally where found = 0 AND deuid = 'orDTdGUMTR4';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (new) 1 - 2 Months', Count(*) from  _momc_tally where found = 0 AND deuid = 'b1zV5iZXXlo';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (new) 2 - 3 Months', Count(*) from  _momc_tally where found = 0 AND deuid = 'vqwlped2JGq';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Converted Reg (new) AFTER 3 Months', Count(*) from  _momc_tally where found = 0 AND deuid = 'dwqkOMJkDhC';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Public Converted Reg (new) AFTER 3 Months', Count(*) from  _momc_tally where found = 0 AND deuid = 'dwqkOMJkDhC';


/* SCRIPT 3: GESTATIONAL AGES from REGISTRATIONS */

truncate table _momc_tally;

/* CREATE Client Registrations with Gestational Age up to and below 20 weeks */
INSERT INTO _momc_tally (organisationunitid,deuid,period,value,storedby,created)
select organisationunitid, 'C5Ih4771Lp4', to_char(dtmPeriod, 'yyyymmdd'), SUM(instances),'aggregated_from_MomScript',CURRENT_DATE FROM (
SELECT 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date as dtmPeriod,
  count(*) as instances
FROM 
  public.programstageinstance, 
  public.trackedentitydatavalue
WHERE 
  trackedentitydatavalue.programstageinstanceid = programstageinstance.programstageinstanceid AND programstageinstance.programstageid = 47888 AND
  trackedentitydatavalue.dataelementid = 7272801 AND trackedentitydatavalue.value <> '0000-00-00' AND
  programstageinstance.programstageinstanceid In (select programstageinstanceid from programstageinstance where executiondate IS NOT NULL AND to_char(executiondate,'yyyy-mm-dd') <> '0000-00-00' AND to_char(executiondate,'yyyy-mm-dd') >= '2014-08-01' AND to_char(executiondate,'yyyy-mm-dd') < to_char(CURRENT_DATE,'yyyy-mm-dd')) AND
  trackedentitydatavalue.value::date - programstageinstance.executiondate::date <= 146
GROUP BY 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date
  ) as Foo
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY organisationunitid, to_char(dtmPeriod, 'yyyymmdd');

/* CREATE Client Registrations with Gestational Age 21 to 34 weeks */
INSERT INTO _momc_tally (organisationunitid,deuid,period,value,storedby,created)
select organisationunitid, 'MYGXCThSFL5', to_char(dtmPeriod, 'yyyymmdd'), SUM(instances),'aggregated_from_MomScript',CURRENT_DATE FROM (
SELECT 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date as dtmPeriod,
  count(*) as instances
FROM 
  public.programstageinstance, 
  public.trackedentitydatavalue
WHERE 
  trackedentitydatavalue.programstageinstanceid = programstageinstance.programstageinstanceid AND programstageinstance.programstageid = 47888 AND
  trackedentitydatavalue.dataelementid = 7272801 AND trackedentitydatavalue.value <> '0000-00-00' AND
  programstageinstance.programstageinstanceid In (select programstageinstanceid from programstageinstance where executiondate IS NOT NULL AND to_char(executiondate,'yyyy-mm-dd') <> '0000-00-00' AND to_char(executiondate,'yyyy-mm-dd') >= '2014-08-01' AND to_char(executiondate,'yyyy-mm-dd') < to_char(CURRENT_DATE,'yyyy-mm-dd')) AND
  trackedentitydatavalue.value::date - programstageinstance.executiondate::date >= 147 AND trackedentitydatavalue.value::date - programstageinstance.executiondate::date < 245
GROUP BY 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date
  ) as Foo
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY organisationunitid, to_char(dtmPeriod, 'yyyymmdd');


/* CREATE Client Registrations with Gestational Age 35 weeks and above */
INSERT INTO _momc_tally (organisationunitid,deuid,period,value,storedby,created)
select organisationunitid, 'q7pKketdbUw', to_char(dtmPeriod, 'yyyymmdd'), SUM(instances),'aggregated_from_MomScript',CURRENT_DATE FROM (
SELECT 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date as dtmPeriod,
  count(*) as instances
FROM 
  public.programstageinstance, 
  public.trackedentitydatavalue
WHERE 
  trackedentitydatavalue.programstageinstanceid = programstageinstance.programstageinstanceid AND programstageinstance.programstageid = 47888 AND
  trackedentitydatavalue.dataelementid = 7272801 AND trackedentitydatavalue.value <> '0000-00-00' AND
  programstageinstance.programstageinstanceid In (select programstageinstanceid from programstageinstance where executiondate IS NOT NULL AND to_char(executiondate,'yyyy-mm-dd') <> '0000-00-00' AND to_char(executiondate,'yyyy-mm-dd') >= '2014-08-01' AND to_char(executiondate,'yyyy-mm-dd') < to_char(CURRENT_DATE,'yyyy-mm-dd')) AND
  trackedentitydatavalue.value::date - programstageinstance.executiondate::date >= 245
GROUP BY 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date
  ) as Foo
GROUP BY organisationunitid, to_char(dtmPeriod, 'yyyymmdd');


UPDATE _momc_tally "A" SET Found = 0;
UPDATE _momc_tally "A" SET periodid = "B".periodid FROM  period "B" WHERE "A".period = to_char("B".startdate, 'yyyymmdd') AND "B".periodtypeid = 1;
UPDATE _momc_tally "A" SET dataelementid = dataelement.dataelementid FROM dataelement WHERE "A".deuid = dataelement.uid;
UPDATE _momc_tally "A" SET found = 1 FROM datavalue "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "B".sourceid = "A".organisationunitid;

/* Update datavalue from temp where values are different */
UPDATE datavalue "A" SET value = "B".value FROM _momc_tally "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "A".sourceid = "B".organisationunitid AND "B".Found <> 0 AND "A".value <> "B".value;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Gestational Age below 20 weeks (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'C5Ih4771Lp4';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Gestational Age 20 to 34 weeks (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'MYGXCThSFL5';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Gestational Age 35 weeks and above (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'q7pKketdbUw';

/* Append New data values */
INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated, followup)
SELECT "A".dataelementid, "A".periodid, "A".organisationunitid, 16, 16, "A".value, "A".storedby, "A".created, "A".lastupdated, FALSE FROM _momc_tally "A" WHERE "A".found <> 1;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Gestational Age below 20 weeks (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'C5Ih4771Lp4';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Gestational Age 20 to 34 weeks (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'MYGXCThSFL5';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Gestational Age 35 weeks and above (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'q7pKketdbUw';


/* SCRIPT 4: Antenatal Visits (Target values) */

truncate table _momc_tally;

/* CREATE Client Registration Target fPrev-Year(of Antenatal 1st visit total) values for 2015+ */
INSERT INTO _momc_tally (organisationunitid,deuid,periodid,value,storedby,created)
select datavalue.sourceid, 'AWXQsENsfoV', datavalue.periodid, cast(datavalue.value as double precision) * 0.6,'aggregated_from_MomScript',CURRENT_DATE
FROM  public.datavalue, public.period
WHERE period.periodid = datavalue.periodid AND period.startdate >= CURRENT_DATE - 90 AND period.startdate <= '2015-12-31' AND datavalue.dataelementid In (select dataelementid from dataelement where uid = 'EMHm9Q75Og1');

/* CREATE Client Registration Target ACTUAL (of Antenatal 1st visit total) values for 2015+ */
INSERT INTO _momc_tally (organisationunitid,deuid,periodid,value,storedby,created)
select datavalue.sourceid, 'eDktBD88IUL', datavalue.periodid, cast(datavalue.value as double precision) * 0.6,'aggregated_from_MomScript',CURRENT_DATE
FROM  public.datavalue, public.period
WHERE period.periodid = datavalue.periodid AND period.startdate >= CURRENT_DATE - 90 AND period.startdate <= '2015-12-31' AND datavalue.dataelementid In (select dataelementid from dataelement where uid = 'Al6K6d7Q5m4');

/* CREATE Client Registration Target (of Antenatal 1st visit before 20 weeks) values for 2015+ */
INSERT INTO _momc_tally (organisationunitid,deuid,periodid,value,storedby,created)
select datavalue.sourceid, 'rIF2YyXrsER', datavalue.periodid, cast(datavalue.value as double precision) * 0.6,'aggregated_from_MomScript',CURRENT_DATE
FROM  public.datavalue, public.period
WHERE period.periodid = datavalue.periodid AND period.startdate >= CURRENT_DATE - 90 AND period.startdate <= '2015-12-31' AND datavalue.dataelementid In (select dataelementid from dataelement where uid = 'Cl4D9i5T6j2');

/* CREATE Client Registration Target (of Antenatal 1st visit 20 weeks or later) values for 2015+ */
INSERT INTO _momc_tally (organisationunitid,deuid,periodid,value,storedby,created)
select datavalue.sourceid, 'rvVE6HN25Vc', datavalue.periodid, cast(datavalue.value as double precision) * 0.6,'aggregated_from_MomScript',CURRENT_DATE
FROM  public.datavalue, public.period
WHERE period.periodid = datavalue.periodid AND period.startdate >= CURRENT_DATE - 90 AND period.startdate <= '2015-12-31' AND datavalue.dataelementid In (select dataelementid from dataelement where uid = 'N2m4W6w3N4r');



/* CREATE Client Registration Target fPrev-Year(of Antenatal 1st visit total) values for 2015+ */
INSERT INTO _momc_tally (organisationunitid,deuid,periodid,value,storedby,created)
select datavalue.sourceid, 'AWXQsENsfoV', datavalue.periodid, cast(datavalue.value as double precision) * 0.8,'aggregated_from_MomScript',CURRENT_DATE
FROM  public.datavalue, public.period
WHERE period.periodid = datavalue.periodid AND period.startdate >= CURRENT_DATE - 90 AND period.startdate >= '2016-01-01' AND datavalue.dataelementid In (select dataelementid from dataelement where uid = 'EMHm9Q75Og1');

/* CREATE Client Registration Target ACTUAL (of Antenatal 1st visit total) values for 2015+ */
INSERT INTO _momc_tally (organisationunitid,deuid,periodid,value,storedby,created)
select datavalue.sourceid, 'eDktBD88IUL', datavalue.periodid, cast(datavalue.value as double precision) * 0.8,'aggregated_from_MomScript',CURRENT_DATE
FROM  public.datavalue, public.period
WHERE period.periodid = datavalue.periodid AND period.startdate >= CURRENT_DATE - 90 AND period.startdate >= '2016-01-01' AND datavalue.dataelementid In (select dataelementid from dataelement where uid = 'Al6K6d7Q5m4');

/* CREATE Client Registration Target (of Antenatal 1st visit before 20 weeks) values for 2015+ */
INSERT INTO _momc_tally (organisationunitid,deuid,periodid,value,storedby,created)
select datavalue.sourceid, 'rIF2YyXrsER', datavalue.periodid, cast(datavalue.value as double precision) * 0.8,'aggregated_from_MomScript',CURRENT_DATE
FROM  public.datavalue, public.period
WHERE period.periodid = datavalue.periodid AND period.startdate >= CURRENT_DATE - 90 AND period.startdate >= '2016-01-01' AND datavalue.dataelementid In (select dataelementid from dataelement where uid = 'Cl4D9i5T6j2');

/* CREATE Client Registration Target (of Antenatal 1st visit 20 weeks or later) values for 2015+ */
INSERT INTO _momc_tally (organisationunitid,deuid,periodid,value,storedby,created)
select datavalue.sourceid, 'rvVE6HN25Vc', datavalue.periodid, cast(datavalue.value as double precision) * 0.8,'aggregated_from_MomScript',CURRENT_DATE
FROM  public.datavalue, public.period
WHERE period.periodid = datavalue.periodid AND period.startdate >= CURRENT_DATE - 90 AND period.startdate >= '2016-01-01' AND datavalue.dataelementid In (select dataelementid from dataelement where uid = 'N2m4W6w3N4r');



UPDATE _momc_tally "A" SET Found = 0;
UPDATE _momc_tally "A" SET dataelementid = dataelement.dataelementid FROM dataelement WHERE "A".deuid = dataelement.uid;
UPDATE _momc_tally "A" SET found = 1 FROM datavalue "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "B".sourceid = "A".organisationunitid;

/* Update datavalue from temp where values are different */
UPDATE datavalue "A" SET value = "B".value FROM _momc_tally "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "A".sourceid = "B".organisationunitid AND "B".Found <> 0 AND "A".value <> "B".value;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Antenatal 1st visit total {fYear} (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'AWXQsENsfoV';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Antenatal 1st visit total (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'eDktBD88IUL';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Antenatal 1st visit before 20 weeks (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'rIF2YyXrsER';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Antenatal 1st visit 20 weeks or later (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'rvVE6HN25Vc';

/* Append New data values */
INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated, followup)
SELECT "A".dataelementid, "A".periodid, "A".organisationunitid, 16, 16, "A".value, "A".storedby, "A".created, "A".lastupdated, FALSE FROM _momc_tally "A" WHERE "A".found <> 1;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Antenatal 1st visit total {fYear} (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'AWXQsENsfoV';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Antenatal 1st visit total (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'eDktBD88IUL';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Antenatal 1st visit before 20 weeks (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'rIF2YyXrsER';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Antenatal 1st visit 20 weeks or later (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'rvVE6HN25Vc';



/* SCRIPT 5: CLIENT AGE COHORTS for REGISTRATIONS */

truncate table _momc_tally;

/* CREATE Client Registrations with Age below 18 years */
INSERT INTO _momc_tally (organisationunitid,deuid,period,value,storedby,created)
select organisationunitid, 'NLCni2oKVGQ', to_char(dtmPeriod, 'yyyymmdd'), Count(*),'aggregated_from_MomScript',CURRENT_DATE FROM (
SELECT 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date as dtmPeriod,
  trackedentitydatavalue.programstageinstanceid
FROM 
  public.programstageinstance, 
  public.trackedentitydatavalue
WHERE 
  trackedentitydatavalue.programstageinstanceid = programstageinstance.programstageinstanceid AND programstageinstance.programstageid = 47888 AND
  trackedentitydatavalue.dataelementid = 7272791 AND trackedentitydatavalue.value <> '0000-00-00' AND
  programstageinstance.programstageinstanceid In (select programstageinstanceid from programstageinstance where executiondate IS NOT NULL AND to_char(executiondate,'yyyy-mm-dd') >= '2014-08-01' AND to_char(executiondate,'yyyy-mm-dd') < to_char(CURRENT_DATE,'yyyy-mm-dd')) AND
  programstageinstance.executiondate::date - trackedentitydatavalue.value::date < 6574 
  ) as Foo
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY organisationunitid, to_char(dtmPeriod, 'yyyymmdd');

/* CREATE Client Registrations with Age between 18 and 19 years */
INSERT INTO _momc_tally (organisationunitid,deuid,period,value,storedby,created)
select organisationunitid, 'YgL5Iwbi8y2', to_char(dtmPeriod, 'yyyymmdd'), Count(*),'aggregated_from_MomScript',CURRENT_DATE FROM (
SELECT 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date as dtmPeriod,
  trackedentitydatavalue.programstageinstanceid
FROM 
  public.programstageinstance, 
  public.trackedentitydatavalue
WHERE 
  trackedentitydatavalue.programstageinstanceid = programstageinstance.programstageinstanceid AND programstageinstance.programstageid = 47888 AND
  trackedentitydatavalue.dataelementid = 7272791 AND trackedentitydatavalue.value <> '0000-00-00' AND
  programstageinstance.programstageinstanceid In (select programstageinstanceid from programstageinstance where executiondate IS NOT NULL AND to_char(executiondate,'yyyy-mm-dd') >= '2014-08-01' AND to_char(executiondate,'yyyy-mm-dd') < to_char(CURRENT_DATE,'yyyy-mm-dd')) AND
  programstageinstance.executiondate::date - trackedentitydatavalue.value::date >= 6574 AND programstageinstance.executiondate::date - trackedentitydatavalue.value::date < 7305
  ) as Foo
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY organisationunitid, to_char(dtmPeriod, 'yyyymmdd');

/* CREATE Client Registrations with Age between 20 and 24 years */
INSERT INTO _momc_tally (organisationunitid,deuid,period,value,storedby,created)
select organisationunitid, 'TMuZs8OgGxm', to_char(dtmPeriod, 'yyyymmdd'), Count(*),'aggregated_from_MomScript',CURRENT_DATE FROM (
SELECT 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date as dtmPeriod,
  trackedentitydatavalue.programstageinstanceid
FROM 
  public.programstageinstance, 
  public.trackedentitydatavalue
WHERE 
  trackedentitydatavalue.programstageinstanceid = programstageinstance.programstageinstanceid AND programstageinstance.programstageid = 47888 AND
  trackedentitydatavalue.dataelementid = 7272791 AND trackedentitydatavalue.value <> '0000-00-00' AND
  programstageinstance.programstageinstanceid In (select programstageinstanceid from programstageinstance where executiondate IS NOT NULL AND to_char(executiondate,'yyyy-mm-dd') >= '2014-08-01' AND to_char(executiondate,'yyyy-mm-dd') < to_char(CURRENT_DATE,'yyyy-mm-dd')) AND
  programstageinstance.executiondate::date - trackedentitydatavalue.value::date >= 7305 AND programstageinstance.executiondate::date - trackedentitydatavalue.value::date < 9131
) as Foo
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY organisationunitid, to_char(dtmPeriod, 'yyyymmdd');

/* CREATE Client Registrations with Age between 25 and 29 years */
INSERT INTO _momc_tally (organisationunitid,deuid,period,value,storedby,created)
select organisationunitid, 'acAMvcueBUb', to_char(dtmPeriod, 'yyyymmdd'), Count(*),'aggregated_from_MomScript',CURRENT_DATE FROM (
SELECT 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date as dtmPeriod,
  trackedentitydatavalue.programstageinstanceid
FROM 
  public.programstageinstance, 
  public.trackedentitydatavalue
WHERE 
  trackedentitydatavalue.programstageinstanceid = programstageinstance.programstageinstanceid AND programstageinstance.programstageid = 47888 AND
  trackedentitydatavalue.dataelementid = 7272791 AND trackedentitydatavalue.value <> '0000-00-00' AND
  programstageinstance.programstageinstanceid In (select programstageinstanceid from programstageinstance where executiondate IS NOT NULL AND to_char(executiondate,'yyyy-mm-dd') >= '2014-08-01' AND to_char(executiondate,'yyyy-mm-dd') < to_char(CURRENT_DATE,'yyyy-mm-dd')) AND
  programstageinstance.executiondate::date - trackedentitydatavalue.value::date >= 9131 AND programstageinstance.executiondate::date - trackedentitydatavalue.value::date < 10957
) as Foo
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY organisationunitid, to_char(dtmPeriod, 'yyyymmdd');

/* CREATE Client Registrations with Age between 30 and 34 years */
INSERT INTO _momc_tally (organisationunitid,deuid,period,value,storedby,created)
select organisationunitid, 'xwadfqcgwDd', to_char(dtmPeriod, 'yyyymmdd'), Count(*),'aggregated_from_MomScript',CURRENT_DATE FROM (
SELECT 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date as dtmPeriod,
  trackedentitydatavalue.programstageinstanceid
FROM 
  public.programstageinstance, 
  public.trackedentitydatavalue
WHERE 
  trackedentitydatavalue.programstageinstanceid = programstageinstance.programstageinstanceid AND programstageinstance.programstageid = 47888 AND
  trackedentitydatavalue.dataelementid = 7272791 AND trackedentitydatavalue.value <> '0000-00-00' AND
  programstageinstance.programstageinstanceid In (select programstageinstanceid from programstageinstance where executiondate IS NOT NULL AND to_char(executiondate,'yyyy-mm-dd') >= '2014-08-01' AND to_char(executiondate,'yyyy-mm-dd') < to_char(CURRENT_DATE,'yyyy-mm-dd')) AND
  programstageinstance.executiondate::date - trackedentitydatavalue.value::date >= 10957 AND programstageinstance.executiondate::date - trackedentitydatavalue.value::date < 12783
) as Foo
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY organisationunitid, to_char(dtmPeriod, 'yyyymmdd');

/* CREATE Client Registrations with Age 35 years and older */
INSERT INTO _momc_tally (organisationunitid,deuid,period,value,storedby,created)
select organisationunitid, 'cI3CB9ZuReX', to_char(dtmPeriod, 'yyyymmdd'), Count(*),'aggregated_from_MomScript',CURRENT_DATE FROM (
SELECT 
  programstageinstance.organisationunitid, 
  programstageinstance.executiondate::date as dtmPeriod,
  trackedentitydatavalue.programstageinstanceid
FROM 
  public.programstageinstance, 
  public.trackedentitydatavalue
WHERE 
  trackedentitydatavalue.programstageinstanceid = programstageinstance.programstageinstanceid AND programstageinstance.programstageid = 47888 AND
  trackedentitydatavalue.dataelementid = 7272791 AND trackedentitydatavalue.value <> '0000-00-00' AND
  programstageinstance.programstageinstanceid In (select programstageinstanceid from programstageinstance where executiondate IS NOT NULL AND to_char(executiondate,'yyyy-mm-dd') >= '2014-08-01' AND to_char(executiondate,'yyyy-mm-dd') < to_char(CURRENT_DATE,'yyyy-mm-dd')) AND
  programstageinstance.executiondate::date - trackedentitydatavalue.value::date >= 12783 
) as Foo
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY organisationunitid, to_char(dtmPeriod, 'yyyymmdd');

UPDATE _momc_tally "A" SET Found = 0;
UPDATE _momc_tally "A" SET periodid = "B".periodid FROM  period "B" WHERE "A".period::date = "B".startdate::date AND "B".periodtypeid = 1;
UPDATE _momc_tally "A" SET dataelementid = dataelement.dataelementid FROM dataelement WHERE "A".deuid = dataelement.uid;
UPDATE _momc_tally "A" SET found = 1 FROM datavalue "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "B".sourceid = "A".organisationunitid;

/* Update datavalue from temp where values are different */
UPDATE datavalue "A" SET value = "B".value FROM _momc_tally "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "A".sourceid = "B".organisationunitid AND "B".Found <> 0 AND "A".value <> "B".value;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age below 18 years (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'NLCni2oKVGQ';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age between 18 and 19 years (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'YgL5Iwbi8y2';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age between 20 and 24 years (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'TMuZs8OgGxm';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age between 25 and 29 years (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'acAMvcueBUb';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age between 30 and 34 years (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'xwadfqcgwDd';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age 35 years and older (updates)', Count(*) from  _momc_tally where found <> 0 AND deuid = 'cI3CB9ZuReX';

/* Append New data values */
INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated, followup)
SELECT "A".dataelementid, "A".periodid, "A".organisationunitid, 16, 16, "A".value, "A".storedby, "A".created, "A".lastupdated, FALSE FROM _momc_tally "A" WHERE "A".found <> 1;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age below 18 years (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'NLCni2oKVGQ';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age between 18 and 19 years (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'YgL5Iwbi8y2';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age between 20 and 24 years (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'TMuZs8OgGxm';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age between 25 and 29 years (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'acAMvcueBUb';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age between 30 and 34 years (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'xwadfqcgwDd';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Client Registrations with Age 35 years and older (new)', Count(*) from  _momc_tally where found = 0 AND deuid = 'cI3CB9ZuReX';



/* SCRIPT 6: SERVICE RATINGS */

truncate table _momc_tally;

/*  C L E A N L I N E S S  */

/* Load Cleanliness (very unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47847, 'pqkO6bKUlsA', 47843, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274875) = '0'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Cleanliness (Unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47847, 'pqkO6bKUlsA', 47840, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274875) = '1'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Cleanliness (satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47847, 'pqkO6bKUlsA', 47842, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274875) = '2'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Cleanliness (Very satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47847, 'pqkO6bKUlsA', 47841, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274875) = '3'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/*  F R I E N D L I N E S S  */

/* Load Friendliness (very unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47844, 'fT0Ij6NxsqF', 47843, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274859) = '0'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Friendliness (Unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47844, 'fT0Ij6NxsqF', 47840, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274859) = '1'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Friendliness (satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47844, 'fT0Ij6NxsqF', 47842, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274859) = '2'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Friendliness (Very satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47844, 'fT0Ij6NxsqF', 47841, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274859) = '3'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/*  P R I V A C Y  */

/* Load Privacy (very unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47848, 'A8YBjNIFEki', 47843, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274887) = '0'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Privacy (Unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47848, 'A8YBjNIFEki', 47840, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274887) = '1'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Privacy (satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47848, 'A8YBjNIFEki', 47842, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274887) = '2'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Privacy (Very satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47848, 'A8YBjNIFEki', 47841, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274887) = '3'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/*  W T - F E E L  */

/* Load Waiting Times Feel (very unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47845, 'LUHydToTpMY', 47843, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274906) = '0'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Waiting Times Feel (Unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47845, 'LUHydToTpMY', 47840, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274906) = '1'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Waiting Times Feel (satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47845, 'LUHydToTpMY', 47842, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274906) = '2'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Waiting Times Feel (Very satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47845, 'LUHydToTpMY', 47841, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274906) = '3'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/*  W T - L E N G T H  */

/* Load Waiting Times Length (very unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47846, 'VVPm3ADvUUK', 47843, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274933) = '0'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Waiting Times Length (Unsatis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47846, 'VVPm3ADvUUK', 47840, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274933) = '1'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Waiting Times Length (satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47846, 'VVPm3ADvUUK', 47842, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274933) = '2'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Waiting Times Length (Very satis) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,categoryoptioncomboid,period,value,storedby,created)
SELECT "A".organisationunitid, 47846, 'VVPm3ADvUUK', 47841, dtmEvent, Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	"PSI".organisationunitid,
	"PSI".programstageinstanceid,
	"PSI".executiondate as dtmPeriod,
	to_char("PSI".executiondate, 'yyyymmdd') as dtmEvent
FROM 
  public.programstageinstance as "PSI", 
  public.programstage as "PS"
WHERE 
  "PSI".programstageid = "PS".programstageid AND to_char("PSI".executiondate, 'yyyymmdd') >= '20140801' AND to_char("PSI".executiondate, 'yyyymmdd') < to_char(CURRENT_DATE,'yyyymmdd') AND
  "PS".uid = 'KISUPJ9InOr' AND (SELECT value FROM trackedentitydatavalue as "C" WHERE "C".programstageinstanceid = "PSI".programstageinstanceid AND "C".dataelementid = 7274933) = '3'
) as "A" 
WHERE dtmPeriod >= CURRENT_DATE - days AND dtmPeriod < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;



UPDATE _momc_tally "A" SET Found = 0;
UPDATE _momc_tally "A" SET periodid = "B".periodid FROM  period "B" WHERE "A".period = to_char("B".startdate, 'yyyymmdd') AND "B".periodtypeid = 1;
UPDATE _momc_tally "A" SET found = 1 FROM datavalue "B" WHERE "A".dataelementid = "B".dataelementid AND "A".categoryoptioncomboid = "B".categoryoptioncomboid AND "A".periodid = "B".periodid AND "B".sourceid = "A".organisationunitid;

/* Update datavalue from temp where values are different */
UPDATE datavalue "A" SET value = "B".value FROM _momc_tally "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "A".sourceid = "B".organisationunitid AND "B".Found <> 0 AND "A".value <> "B".value;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Cleanliness: very unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47847 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Cleanliness: unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47847 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Cleanliness: satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47847 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Cleanliness: very satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47847 AND categoryoptioncomboid = 47841;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Friendliness: very unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47844 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Friendliness: unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47844 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Friendliness: satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47844 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Friendliness: very satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47844 AND categoryoptioncomboid = 47841;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Privacy: very unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47848 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Privacy: unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47848 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Privacy: satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47848 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Privacy: very satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47848 AND categoryoptioncomboid = 47841;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Feel: very unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47845 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Feel: unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47845 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Feel: satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47845 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Feel: very satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47845 AND categoryoptioncomboid = 47841;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Length: very unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47846 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Length: unsatis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47846 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Length: satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47846 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Length: very satis (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 47846 AND categoryoptioncomboid = 47841;


/* Append New data values */
INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated, followup)
SELECT "A".dataelementid, "A".periodid, "A".organisationunitid, categoryoptioncomboid, categoryoptioncomboid, "A".value, "A".storedby, "A".created, "A".lastupdated, FALSE FROM _momc_tally "A" WHERE "A".found <> 1;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Cleanliness: very unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47847 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Cleanliness: unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47847 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Cleanliness: satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47847 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Cleanliness: very satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47847 AND categoryoptioncomboid = 47841;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Friendliness: very unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47844 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Friendliness: unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47844 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Friendliness: satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47844 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Friendliness: very satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47844 AND categoryoptioncomboid = 47841;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Privacy: very unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47848 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Privacy: unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47848 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Privacy: satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47848 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Privacy: very satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47848 AND categoryoptioncomboid = 47841;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Feel: very unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47845 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Feel: unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47845 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Feel: satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47845 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Feel: very satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47845 AND categoryoptioncomboid = 47841;

insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Length: very unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47846 AND categoryoptioncomboid = 47843;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Length: unsatis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47846 AND categoryoptioncomboid = 47840;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Length: satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47846 AND categoryoptioncomboid = 47842;
insert into _momc_log (datetime, operation, rowcount) select now(), 'SR Waiting Times Length: very satis (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 47846 AND categoryoptioncomboid = 47841;



/* SCRIPT 7: OPT-OUTS */

truncate table _momc_tally;

/* Load Client Opt-Out (Total) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,period,value,storedby,created)
SELECT "A".organisationunitid, 7625870, 'hpqmFs8Bioo', to_char(dtmEvent, 'yyyymmdd'), Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	  "PSI".programstageinstanceid, 
	  "PSI".organisationunitid, 
	  "PSI".executiondate as dtmEvent
	FROM 
	  public.programstageinstance "PSI", 
	  public.programinstance "PI"
	WHERE 
	  "PSI".programinstanceid = "PI".programinstanceid AND
	  "PSI".programstageid = 56636 
	GROUP BY
	  "PSI".programstageinstanceid, 
	  "PSI".organisationunitid, 
	  "PSI".executiondate
) as "A" 
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Client Opt-Out (Miscarriage) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,period,value,storedby,created)
SELECT "A".organisationunitid, 7625955, 'cWINDGfKIGX', to_char(dtmEvent, 'yyyymmdd'), Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	  "PSI".programstageinstanceid, 
	  "PSI".organisationunitid, 
	  "PSI".executiondate as dtmEvent, 
	  "TEAV".value as "Mom_Sub_Cell_Number", 
	  "DVAL".value as "Opt_Out_Code"
	FROM 
	  public.trackedentitydatavalue "DVAL", 
	  public.programstageinstance "PSI", 
	  public.dataelement, 
	  public.trackedentityattributevalue "TEAV", 
	  public.programinstance "PI", 
	  public.trackedentityattribute
	WHERE 
	  "DVAL".dataelementid = dataelement.dataelementid AND
	  "PSI".programstageinstanceid = "DVAL".programstageinstanceid AND
	  "PSI".programinstanceid = "PI".programinstanceid AND
	  "TEAV".trackedentityinstanceid = "PI".trackedentityinstanceid AND
	  trackedentityattribute.trackedentityattributeid = "TEAV".trackedentityattributeid AND
	  "PSI".programstageid = 56636 AND 
	  "DVAL".dataelementid = 56643 AND "DVAL".value = '1'
) as "A" 
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Client Opt-Out (Stillborn) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,period,value,storedby,created)
SELECT "A".organisationunitid, 7625965, 'NFLOBi1U6tr', to_char(dtmEvent, 'yyyymmdd'), Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	  "PSI".programstageinstanceid, 
	  "PSI".organisationunitid, 
	  "PSI".executiondate as dtmEvent, 
	  "TEAV".value as "Mom_Sub_Cell_Number", 
	  "DVAL".value as "Opt_Out_Code"
	FROM 
	  public.trackedentitydatavalue "DVAL", 
	  public.programstageinstance "PSI", 
	  public.dataelement, 
	  public.trackedentityattributevalue "TEAV", 
	  public.programinstance "PI", 
	  public.trackedentityattribute
	WHERE 
	  "DVAL".dataelementid = dataelement.dataelementid AND
	  "PSI".programstageinstanceid = "DVAL".programstageinstanceid AND
	  "PSI".programinstanceid = "PI".programinstanceid AND
	  "TEAV".trackedentityinstanceid = "PI".trackedentityinstanceid AND
	  trackedentityattribute.trackedentityattributeid = "TEAV".trackedentityattributeid AND
	  "PSI".programstageid = 56636 AND 
	  "DVAL".dataelementid = 56643 AND "DVAL".value = '2'
) as "A" 
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;

/* Load Client Opt-Out (Baby Loss) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,period,value,storedby,created)
SELECT "A".organisationunitid, 7625978, 'eOd1MPvggRe', to_char(dtmEvent, 'yyyymmdd'), Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	  "PSI".programstageinstanceid, 
	  "PSI".organisationunitid, 
	  "PSI".executiondate as dtmEvent, 
	  "TEAV".value as "Mom_Sub_Cell_Number", 
	  "DVAL".value as "Opt_Out_Code"
	FROM 
	  public.trackedentitydatavalue "DVAL", 
	  public.programstageinstance "PSI", 
	  public.dataelement, 
	  public.trackedentityattributevalue "TEAV", 
	  public.programinstance "PI", 
	  public.trackedentityattribute
	WHERE 
	  "DVAL".dataelementid = dataelement.dataelementid AND
	  "PSI".programstageinstanceid = "DVAL".programstageinstanceid AND
	  "PSI".programinstanceid = "PI".programinstanceid AND
	  "TEAV".trackedentityinstanceid = "PI".trackedentityinstanceid AND
	  trackedentityattribute.trackedentityattributeid = "TEAV".trackedentityattributeid AND
	  "PSI".programstageid = 56636 AND 
	  "DVAL".dataelementid = 56643 AND "DVAL".value = '3'
) as "A" 
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;


/* Load Client Opt-Out (Not Useful) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,period,value,storedby,created)
SELECT "A".organisationunitid, 7625985, 'AhWkcuYu0dw', to_char(dtmEvent, 'yyyymmdd'), Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	  "PSI".programstageinstanceid, 
	  "PSI".organisationunitid, 
	  "PSI".executiondate as dtmEvent, 
	  "TEAV".value as "Mom_Sub_Cell_Number", 
	  "DVAL".value as "Opt_Out_Code"
	FROM 
	  public.trackedentitydatavalue "DVAL", 
	  public.programstageinstance "PSI", 
	  public.dataelement, 
	  public.trackedentityattributevalue "TEAV", 
	  public.programinstance "PI", 
	  public.trackedentityattribute
	WHERE 
	  "DVAL".dataelementid = dataelement.dataelementid AND
	  "PSI".programstageinstanceid = "DVAL".programstageinstanceid AND
	  "PSI".programinstanceid = "PI".programinstanceid AND
	  "TEAV".trackedentityinstanceid = "PI".trackedentityinstanceid AND
	  trackedentityattribute.trackedentityattributeid = "TEAV".trackedentityattributeid AND
	  "PSI".programstageid = 56636 AND 
	  "DVAL".dataelementid = 56643 AND "DVAL".value = '4'
) as "A" 
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;


/* Load Client Opt-Out (Other) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,period,value,storedby,created)
SELECT "A".organisationunitid, 7625994, 'Z1LAu42DLii', to_char(dtmEvent, 'yyyymmdd'), Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	  "PSI".programstageinstanceid, 
	  "PSI".organisationunitid, 
	  "PSI".executiondate as dtmEvent, 
	  "TEAV".value as "Mom_Sub_Cell_Number", 
	  "DVAL".value as "Opt_Out_Code"
	FROM 
	  public.trackedentitydatavalue "DVAL", 
	  public.programstageinstance "PSI", 
	  public.dataelement, 
	  public.trackedentityattributevalue "TEAV", 
	  public.programinstance "PI", 
	  public.trackedentityattribute
	WHERE 
	  "DVAL".dataelementid = dataelement.dataelementid AND
	  "PSI".programstageinstanceid = "DVAL".programstageinstanceid AND
	  "PSI".programinstanceid = "PI".programinstanceid AND
	  "TEAV".trackedentityinstanceid = "PI".trackedentityinstanceid AND
	  trackedentityattribute.trackedentityattributeid = "TEAV".trackedentityattributeid AND
	  "PSI".programstageid = 56636 AND 
	  "DVAL".dataelementid = 56643 AND "DVAL".value = '5'
) as "A" 
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;


/* Load Client Opt-Out (Unknown) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,dataelementid,uid1,period,value,storedby,created)
SELECT "A".organisationunitid, 7625995, 'XKL2823Pahh', to_char(dtmEvent, 'yyyymmdd'), Count(*), 'aggregated_from_MomScript',CURRENT_DATE FROM (
  SELECT 
	  "PSI".programstageinstanceid, 
	  "PSI".organisationunitid, 
	  "PSI".executiondate as dtmEvent, 
	  "TEAV".value as "Mom_Sub_Cell_Number", 
	  "DVAL".value as "Opt_Out_Code"
	FROM 
	  public.trackedentitydatavalue "DVAL", 
	  public.programstageinstance "PSI", 
	  public.dataelement, 
	  public.trackedentityattributevalue "TEAV", 
	  public.programinstance "PI", 
	  public.trackedentityattribute
	WHERE 
	  "DVAL".dataelementid = dataelement.dataelementid AND
	  "PSI".programstageinstanceid = "DVAL".programstageinstanceid AND
	  "PSI".programinstanceid = "PI".programinstanceid AND
	  "TEAV".trackedentityinstanceid = "PI".trackedentityinstanceid AND
	  trackedentityattribute.trackedentityattributeid = "TEAV".trackedentityattributeid AND
	  "PSI".programstageid = 56636 AND 
	  "DVAL".dataelementid = 56643 AND "DVAL".value = '6'
) as "A" 
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY "A".organisationunitid, dtmEvent;


/* Load Registrations electing Opt-Out (Total) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'zfzZ6HVoUme', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "REG".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "REG", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "REG".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "REG".programstageid = 47888 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Registrations electing Opt-Out (Baby Loss) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'W9G4iThhxk8', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "REG".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "REG", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "REG".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "REG".programstageid = 47888 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '3' 
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Registrations electing Opt-Out (Miscarriage) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'fSoiBERELzx', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "REG".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "REG", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "REG".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "REG".programstageid = 47888 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '1' 
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Registrations electing Opt-Out (Stillborn) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'QBrBqWzyp9I', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "REG".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "REG", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "REG".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "REG".programstageid = 47888 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '2' 
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Registrations electing Opt-Out (Not Usefull) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'HCRXZtoEfy3', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "REG".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "REG", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "REG".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "REG".programstageid = 47888 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '4' 
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Registrations electing Opt-Out (Other) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'XIiR4OWmaYK', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "REG".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "REG", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "REG".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "REG".programstageid = 47888 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '5' 
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Registrations electing Opt-Out (Unknown) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'X96rnUsY9OA', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "REG".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "REG", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "REG".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "REG".programstageid = 47888 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '6' 
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;


/* Load Identified by CHW electing Opt-Out (Total) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'XsUGgfaHBHJ', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "CHW".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "CHW", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "CHW".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "CHW".programstageid = 47887 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value in ('1','2','3','4','5','6') AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Identified by CHW electing Opt-Out (Baby Loss) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'kmbRUku0NP9', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "CHW".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "CHW", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "CHW".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "CHW".programstageid = 47887 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '3' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Identified by CHW electing Opt-Out (Miscarriage) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'cxtl2ySg89v', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "CHW".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "CHW", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "CHW".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "CHW".programstageid = 47887 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '1' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Identified by CHW electing Opt-Out (Stillborn) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'uBfhebWbpcb', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "CHW".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "CHW", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "CHW".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "CHW".programstageid = 47887 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '2' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Identified by CHW electing Opt-Out (Not Usefull) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'QFT6OGAgbnE', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "CHW".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "CHW", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "CHW".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "CHW".programstageid = 47887 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '4' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Identified by CHW electing Opt-Out (Other) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'ZTKTfZ1f5Vd', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "CHW".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "CHW", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "CHW".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "CHW".programstageid = 47887 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '5' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Identified by CHW electing Opt-Out (Unknown) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'IHjLAGQkEwJ', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "CHW".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "CHW", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "CHW".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "CHW".programstageid = 47887 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '6' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;




/* Load Subscribers electing Opt-Out (Total) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'd2TERGlJ8NT', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "SUB".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "SUB", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "SUB".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "SUB".programstageid = 47886 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value in ('1','2','3','4','5','6') AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Subscribers electing Opt-Out (Baby Loss) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'zh1r1Po9VXF', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "SUB".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "SUB", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "SUB".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "SUB".programstageid = 47886 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '3' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Subscribers electing Opt-Out (Miscarriage) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'u6ZtJoXB3qg', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "SUB".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "SUB", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "SUB".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "SUB".programstageid = 47886 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '1' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Subscribers electing Opt-Out (Stillborn) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'Gvqhp2WNu3F', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "SUB".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "SUB", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "SUB".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "SUB".programstageid = 47886 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '2' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Subscribers electing Opt-Out (Not Usefull) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'OpgAaBSmGUG', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "SUB".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "SUB", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "SUB".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "SUB".programstageid = 47886 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '4' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Subscribers electing Opt-Out (Other) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'NDMz6RdbhWy', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "SUB".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "SUB", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "SUB".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "SUB".programstageid = 47886 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '5' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Subscribers electing Opt-Out (Unknown) per OrgUnit per Day */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'k37vhwhHjUX', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "SUB".organisationunitid, 
  "OPT".executiondate as dtmEvent, 
  "OPT".programstageinstanceid
FROM 
  public.programinstance "PI", 
  public.programstageinstance "SUB", 
  public.programstageinstance "OPT", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "OPT".programinstanceid AND
  "SUB".programinstanceid = "PI".programinstanceid AND
  "TED".programstageinstanceid = "OPT".programstageinstanceid AND
  "SUB".programstageid = 47886 AND 
  "OPT".programstageid = 56636 AND 
  "TED".dataelementid = 56643 AND "TED".value = '6' AND 
  "PI".programinstanceid Not In (SELECT programinstanceid FROM programstageinstance WHERE programstageid = 47888)
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;



UPDATE _momc_tally "A" SET Found = 0;
UPDATE _momc_tally "A" SET periodid = "B".periodid FROM  period "B" WHERE "A".period = to_char("B".startdate, 'yyyymmdd') AND "B".periodtypeid = 1;
UPDATE _momc_tally "A" SET dataelementid = "B".dataelementid FROM  dataelement "B" WHERE "A".uid1 = "B".uid;
UPDATE _momc_tally "A" SET found = 1 FROM datavalue "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "B".sourceid = "A".organisationunitid;

/* Update datavalue from temp where values are different */
UPDATE datavalue "A" SET value = "B".value FROM _momc_tally "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "A".sourceid = "B".organisationunitid AND "B".Found <> 0 AND "A".value <> "B".value;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Total (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7625870;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Miscarriage (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7625955;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Stillborn (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7625965;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Baby Loss (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7625978;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Not Useful (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7625985;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Other (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7625994;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Unknown (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7625995;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Total (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7647403;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Miscarriage (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7647408;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Stillborn (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7647411;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Baby Loss (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7647407;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Not Useful (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7647409;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Other (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7647410;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Unknown (updates)', Count(*) from  _momc_tally where found <> 0 AND dataelementid = 7647412;

insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Total (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'XsUGgfaHBHJ';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Miscarriage (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'cxtl2ySg89v';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Stillborn (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'uBfhebWbpcb';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Baby Loss (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'kmbRUku0NP9';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Not Useful (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'QFT6OGAgbnE';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Other (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'ZTKTfZ1f5Vd';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Unknown (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'IHjLAGQkEwJ';

insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Total (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'd2TERGlJ8NT';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Miscarriage (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'u6ZtJoXB3qg';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Stillborn (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'Gvqhp2WNu3F';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Baby Loss (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'zh1r1Po9VXF';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Not Useful (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'OpgAaBSmGUG';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Other (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'NDMz6RdbhWy';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Unknown (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'k37vhwhHjUX';

/* Append New data values */
INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated, followup)
SELECT "A".dataelementid, "A".periodid, "A".organisationunitid, 16, 16, "A".value, "A".storedby, "A".created, "A".lastupdated, FALSE FROM _momc_tally "A" WHERE "A".found <> 1;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Total (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7625870;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Miscarriage (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7625955;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Stillborn (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7625965;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Baby Loss (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7625978;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Not Useful (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7625985;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Other (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7625994;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Opt-Out: Unknown (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7625995;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Total (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7647403;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Miscarriage (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7647408;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Stillborn (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7647411;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Baby Loss (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7647407;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Not Useful (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7647409;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Other (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7647410;
insert into _momc_log (datetime, operation, rowcount) select now(), 'Registration Opt-Out: Unknown (new)', Count(*) from  _momc_tally where found = 0 AND dataelementid = 7647412;

insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Total (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'XsUGgfaHBHJ';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Miscarriage (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'cxtl2ySg89v';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Stillborn (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'uBfhebWbpcb';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Baby Loss (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'kmbRUku0NP9';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Not Useful (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'QFT6OGAgbnE';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Other (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'ZTKTfZ1f5Vd';
insert into _momc_log (datetime, operation, rowcount) select now(), 'CHW Identified Opt-Out: Unknown (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'IHjLAGQkEwJ';

insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Total (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'd2TERGlJ8NT';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Miscarriage (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'u6ZtJoXB3qg';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Stillborn (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'Gvqhp2WNu3F';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Baby Loss (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'zh1r1Po9VXF';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Not Useful (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'OpgAaBSmGUG';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Other (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'NDMz6RdbhWy';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Subscriber Opt-Out: Unknown (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'k37vhwhHjUX';

truncate table _momc_tally;

/* SCRIPT 8: HELPDESK DATA */
 
/* Load Help Desk COMPLIMENTS */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'iL600oV2Aom', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "HELP".organisationunitid, 
  "HELP".executiondate as dtmEvent, 
  "HELP".programstageinstanceid,
  "TED".value
FROM 
  public.programinstance "PI", 
  public.programstageinstance "HELP", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "HELP".programinstanceid AND
  "TED".programstageinstanceid = "HELP".programstageinstanceid AND
  "HELP".programstageid = 7872265 AND 
  "TED".dataelementid = 7872267 AND "TED".value::varchar like 'compliment' AND 
  "HELP".executiondate >= CURRENT_DATE - days AND "HELP".executiondate < CURRENT_DATE
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

/* Load Help Desk COMPLAINTS */
INSERT INTO _momc_tally (organisationunitid,uid1,period,value,storedby,created)
select organisationunitid, 'VGy28K3ts9N', to_char(dtmEvent, 'yyyymmdd'), COUNT(*), 'aggregated_from_MomScript',CURRENT_DATE from (
SELECT 
  "HELP".organisationunitid, 
  "HELP".executiondate as dtmEvent, 
  "HELP".programstageinstanceid,
  "TED".value
FROM 
  public.programinstance "PI", 
  public.programstageinstance "HELP", 
  public.trackedentitydatavalue "TED"
WHERE 
  "PI".programinstanceid = "HELP".programinstanceid AND
  "TED".programstageinstanceid = "HELP".programstageinstanceid AND
  "HELP".programstageid = 7872265 AND 
  "TED".dataelementid = 7872267 AND "TED".value::varchar like 'complaint' AND 
  "HELP".executiondate >= CURRENT_DATE - days AND "HELP".executiondate < CURRENT_DATE
) as foo
WHERE dtmEvent >= CURRENT_DATE - days AND dtmEvent < CURRENT_DATE
GROUP BY organisationunitid, dtmEvent;

UPDATE _momc_tally "A" SET Found = 0;
UPDATE _momc_tally "A" SET periodid = "B".periodid FROM  period "B" WHERE "A".period = to_char("B".startdate, 'yyyymmdd') AND "B".periodtypeid = 1;
UPDATE _momc_tally "A" SET dataelementid = "B".dataelementid FROM  dataelement "B" WHERE "A".uid1 = "B".uid;

/* Flag records already present in DataValues (to avoid errors appending Unique-Index-Violations) */
UPDATE _momc_tally "A" SET found = 1 FROM datavalue "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "B".sourceid = "A".organisationunitid;

/* Update datavalue from temp where values are different */
UPDATE datavalue "A" SET value = "B".value FROM _momc_tally "B" WHERE "A".dataelementid = "B".dataelementid AND "A".periodid = "B".periodid AND "A".sourceid = "B".organisationunitid AND "B".Found <> 0 AND "A".value <> "B".value;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Helpdesk: COMPLIMENTS (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'iL600oV2Aom';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Helpdesk: COMPLAINTS (updates)', Count(*) from  _momc_tally where found <> 0 AND uid1 = 'VGy28K3ts9N';

/* Append New data values */
INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated, followup)
SELECT "A".dataelementid, "A".periodid, "A".organisationunitid, 16, 16, "A".value, "A".storedby, "A".created, "A".lastupdated, FALSE FROM _momc_tally "A" WHERE "A".found <> 1;

insert into _momc_log (datetime, operation, rowcount) select now(), 'Helpdesk: COMPLIMENTS (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'iL600oV2Aom';
insert into _momc_log (datetime, operation, rowcount) select now(), 'Helpdesk: COMPLAINTS (new)', Count(*) from  _momc_tally where found = 0 AND uid1 = 'VGy28K3ts9N';

select datetime, operation, rowcount from _momc_log order by operation;
; $BODY$
  LANGUAGE sql VOLATILE
  COST 100
  ROWS 1000;
ALTER FUNCTION momconnect_aggregate_all_before_today_parmDays(integer)
  OWNER TO pgremote;