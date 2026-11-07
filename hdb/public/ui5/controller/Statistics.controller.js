sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/base/strings/formatMessage",
	"sap/ui/model/json/JSONModel",
	"hdb/client/controller/values"
], function (Controller, formatMessage, JSONModel, values) {
	"use strict";

	/** Statistik kommt wie die Sicherungen aus der REST-API: sie gehört zu keinem Entity Set. */
	return Controller.extend("hdb.client.controller.Statistics", {
		formatSize: values.size,
		formatMessage: formatMessage,

		onInit: function () {
			this.getView().setModel(new JSONModel({ busy: false, totals: {}, merge: {}, tables: [], columns: [] }), "view");
			this.getOwnerComponent().getRouter().getRoute("statistics").attachPatternMatched(this._load, this);
		},

		_load: function () {
			const component = this.getOwnerComponent();
			const view = this.getView().getModel("view");
			view.setProperty("/busy", true);
			this.byId("error").setVisible(false);
			return Promise.all([component.authFetch("/api/v1/stats"), component.authFetch("/api/v1/merge")]).then(function (responses) {
				return Promise.all(responses.map(function (response) {
					return response.json();
				}));
			}).then(function (results) {
				view.setData(Object.assign(this._summarize(results[0]), { busy: false, merge: results[1] }), true);
			}.bind(this)).catch(this._fail.bind(this));
		},

		/** Alle Spalten einer Tabelle haben dieselbe Zeilenzahl: das Delta der Tabelle ist das größte ihrer Spalten. */
		_summarize: function (stats) {
			const totals = { tables: stats.length, columns: 0, rows: 0, deltaRows: 0, deletedRows: 0, codeBytes: 0 };
			const columns = [];
			const tables = stats.map(function (table) {
				const deltaRows = Math.max.apply(null, [0].concat(table.columns.map(function (column) {
					return column.deltaRows;
				})));
				const codeBytes = table.columns.reduce(function (sum, column) {
					return sum + column.mainCodeBytes;
				}, 0);
				table.columns.forEach(function (column) {
					columns.push(Object.assign({ table: table.table }, column));
				});
				totals.columns += table.columns.length;
				totals.rows += table.rows;
				totals.deltaRows += deltaRows;
				totals.deletedRows += table.deletedRows;
				totals.codeBytes += codeBytes;
				return {
					table: table.table, storage: table.storage, columnCount: table.columns.length,
					rows: table.rows, deltaRows: deltaRows, deletedRows: table.deletedRows, codeBytes: codeBytes
				};
			});
			return { totals: totals, tables: tables, columns: columns };
		},

		_fail: function (error) {
			this.getView().getModel("view").setProperty("/busy", false);
			if (this.getOwnerComponent().handleError(error)) {
				return;
			}
			const strip = this.byId("error");
			strip.setText(error.message);
			strip.setVisible(true);
		},

		onRefresh: function () {
			this._load();
		},

		onClose: function () {
			this.getOwnerComponent().getRouter().navTo("home");
		}
	});
});
