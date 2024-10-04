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
    relatedprods jsonb
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
-- Name: products_bigid_idx; Type: INDEX; Schema: public; Owner: eugene
--

CREATE UNIQUE INDEX products_bigid_idx ON public.products USING btree (bigid);


--
-- Name: skus_bigid_skuid_idx; Type: INDEX; Schema: public; Owner: eugene
--

CREATE UNIQUE INDEX skus_bigid_skuid_idx ON public.skus USING btree (bigid, skuid);


--
-- PostgreSQL database dump complete
--

