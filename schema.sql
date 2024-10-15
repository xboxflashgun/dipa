--
-- PostgreSQL database dump
--

-- Dumped from database version 17.0 (Ubuntu 17.0-1.pgdg24.04+1)
-- Dumped by pg_dump version 17.0 (Ubuntu 17.0-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bc360list; Type: TABLE; Schema: public; Owner: eugene
--

CREATE TABLE public.bc360list (
    legacyid uuid NOT NULL,
    bingid uuid
);


ALTER TABLE public.bc360list OWNER TO eugene;

--
-- Name: pricehistory; Type: TABLE; Schema: public; Owner: eugene
--

CREATE TABLE public.pricehistory (
    stdate timestamp without time zone,
    msrpp double precision,
    listprice double precision,
    ndays integer,
    bigid text,
    skuid text,
    region text,
    remid text
);


ALTER TABLE public.pricehistory OWNER TO eugene;

--
-- Name: prices; Type: TABLE; Schema: public; Owner: eugene
--

CREATE TABLE public.prices (
    stdate timestamp without time zone,
    enddate timestamp without time zone,
    msrpp double precision,
    listprice double precision,
    bigid text,
    skuid text,
    region text,
    remid text,
    lastmodified timestamp without time zone
);


ALTER TABLE public.prices OWNER TO eugene;

--
-- Name: products; Type: TABLE; Schema: public; Owner: eugene
--

CREATE TABLE public.products (
    released timestamp without time zone,
    bigid text,
    name text,
    type text,
    developer text,
    publisher text,
    category text,
    categories text[],
    optimized text[],
    compatible text[],
    attributes jsonb,
    relatedprods jsonb,
    xbox360 boolean,
    titleid bigint
);


ALTER TABLE public.products OWNER TO eugene;

--
-- Name: skus; Type: TABLE; Schema: public; Owner: eugene
--

CREATE TABLE public.skus (
    bigid text,
    skuid text,
    skuname text,
    skutype text,
    bundledskus jsonb
);


ALTER TABLE public.skus OWNER TO eugene;

--
-- Name: bc360list bc360list_pkey; Type: CONSTRAINT; Schema: public; Owner: eugene
--

ALTER TABLE ONLY public.bc360list
    ADD CONSTRAINT bc360list_pkey PRIMARY KEY (legacyid);


--
-- Name: pricehistory_bigid_skuid_region_remid_idx; Type: INDEX; Schema: public; Owner: eugene
--

CREATE INDEX pricehistory_bigid_skuid_region_remid_idx ON public.pricehistory USING btree (bigid, skuid, region, remid);


--
-- Name: pricehistory_stdate_bigid_skuid_region_remid_idx; Type: INDEX; Schema: public; Owner: eugene
--

CREATE UNIQUE INDEX pricehistory_stdate_bigid_skuid_region_remid_idx ON public.pricehistory USING btree (stdate, bigid, skuid, region, remid);


--
-- Name: prices_bigid_skuid_region_remid_stdate_idx; Type: INDEX; Schema: public; Owner: eugene
--

CREATE UNIQUE INDEX prices_bigid_skuid_region_remid_stdate_idx ON public.prices USING btree (bigid, skuid, region, remid, stdate);


--
-- Name: products_bigid_idx; Type: INDEX; Schema: public; Owner: eugene
--

CREATE UNIQUE INDEX products_bigid_idx ON public.products USING btree (bigid);


--
-- Name: skus_bigid_skuid_idx; Type: INDEX; Schema: public; Owner: eugene
--

CREATE UNIQUE INDEX skus_bigid_skuid_idx ON public.skus USING btree (bigid, skuid);


--
-- Name: prices prices_min_update; Type: TRIGGER; Schema: public; Owner: eugene
--

CREATE TRIGGER prices_min_update BEFORE UPDATE ON public.prices FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();


--
-- Name: products products_min_update; Type: TRIGGER; Schema: public; Owner: eugene
--

CREATE TRIGGER products_min_update BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();


--
-- PostgreSQL database dump complete
--

