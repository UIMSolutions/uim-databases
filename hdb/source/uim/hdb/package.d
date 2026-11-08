/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb;

@safe:

public:
    import uim.oop;

    import uim.hdb.application;
    import uim.hdb.domain;
    import uim.hdb.infrastructure;
    import uim.hdb.presentation;
    import uim.hdb.adapters;

    import uim.hdb.adapters.inbound.admin_web;
    import uim.hdb.adapters.inbound.rest_api;
    import uim.hdb.adapters.inbound.security;
    import uim.hdb.adapters.outbound.file_tenant_storage;
    import uim.hdb.adapters.outbound.file_tenant_store;
    import uim.hdb.adapters.outbound.file_user_store;
    import uim.hdb.adapters.outbound.file_statement_log;
    import uim.hdb.adapters.outbound.openssl_credential_crypto;
    import uim.hdb.adapters.outbound.replication_http;

    import std.algorithm;
    import std.array;
    import std.conv;
    import std.functional;
    import std.path;
    import std.process;
    import std.string;
    import std.uni;
    import std.file;
    import std.stdio;

    import vibe.d;
