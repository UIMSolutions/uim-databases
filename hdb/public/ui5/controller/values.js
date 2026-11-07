sap.ui.define([], function () {
	"use strict";

	const SMALL_INTEGERS = ["Edm.Byte", "Edm.SByte", "Edm.Int16", "Edm.Int32"];
	const FLOATS = ["Edm.Single", "Edm.Double"];

	function point(coordinates) {
		return coordinates.join(" ");
	}

	function line(points) {
		return points.map(point).join(", ");
	}

	/** GeoJSON als WKT: so steht der Wert auch in SQL, und er passt in ein Eingabefeld. */
	function wkt(geo) {
		switch (geo.type) {
			case "Point":
				return "POINT(" + point(geo.coordinates) + ")";
			case "LineString":
				return "LINESTRING(" + line(geo.coordinates) + ")";
			case "Polygon":
				return "POLYGON(" + geo.coordinates.map(function (ring) {
					return "(" + line(ring) + ")";
				}).join(", ") + ")";
			default:
				return JSON.stringify(geo);
		}
	}

	function coordinates(text) {
		const numbers = text.trim().split(/\s+/).map(Number);
		if (numbers.length !== 2 || !numbers.every(Number.isFinite)) {
			throw new Error("invalidGeo");
		}
		return numbers;
	}

	function points(text) {
		return text.split(",").map(coordinates);
	}

	/** WKT als GeoJSON; ob die Geometrie gültig ist, prüft der Server. */
	function geoJson(text) {
		const match = /^\s*(POINT|LINESTRING|POLYGON)\s*\((.*)\)\s*$/i.exec(text);
		if (!match) {
			throw new Error("invalidGeo");
		}
		switch (match[1].toUpperCase()) {
			case "POINT":
				return { type: "Point", coordinates: coordinates(match[2]) };
			case "LINESTRING":
				return { type: "LineString", coordinates: points(match[2]) };
			default:
				return { type: "Polygon", coordinates: (match[2].match(/\([^()]*\)/g) || []).map(function (ring) {
					return points(ring.slice(1, -1));
				}) };
		}
	}

	return {
		size: function (bytes) {
			if (bytes < 1024) {
				return bytes + " B";
			}
			return bytes < 1048576 ? (bytes / 1024).toFixed(1) + " KB" : (bytes / 1048576).toFixed(1) + " MB";
		},

		/** Felder mit Zahlentastatur; Edm.Int64 und Edm.Decimal gehören dazu, obwohl sie als Text übertragen werden. */
		isNumber: function (column) {
			return column.type === "Edm.Int64" || column.type === "Edm.Decimal"
				|| SMALL_INTEGERS.includes(column.type) || FLOATS.includes(column.type);
		},

		/** Für diese Typen hat UI5 keinen Anzeigetyp: Edm.Binary und Edm.Duration fallen auf Raw zurück, Geo-Werte sind Objekte. */
		needsFormatter: function (column) {
			return column.type === "Edm.Binary" || column.type === "Edm.Duration" || /^Edm\.Geo/.test(column.type);
		},

		/**
		 * Formulartext in den Modellwert: Edm.Int64 und Edm.Decimal bleiben Text, weil JavaScript große Werte nicht
		 * exakt darstellt; andere Zahlen werden Zahlen. Alles Übrige prüft der Server. Leere Felder sind NULL.
		 * Wirft mit dem i18n-Schlüssel, wenn die Eingabe nicht passt.
		 */
		parse: function (column, text) {
			const value = text.trim();
			if (column.type === "Edm.String") {
				return text === "" ? null : text;
			}
			if (value === "") {
				return null;
			}
			if (column.type === "Edm.Boolean") {
				if (value !== "true" && value !== "false") {
					throw new Error("invalidBoolean");
				}
				return value === "true";
			}
			if (!this.isNumber(column)) {
				return value;
			}
			if (column.type === "Edm.Int64" || SMALL_INTEGERS.includes(column.type)) {
				if (!/^-?\d+$/.test(value)) {
					throw new Error("invalidInteger");
				}
				return column.type === "Edm.Int64" ? value : Number(value);
			}
			const number = Number(value);
			if (!Number.isFinite(number)) {
				throw new Error("invalidNumber");
			}
			return column.type === "Edm.Decimal" ? value : number;
		},

		/**
		 * Wie parse, aber für neue Zeilen: Geo-Werte müssen hier GeoJSON sein. Das Modell legt die Antwort des Servers
		 * über die gesendeten Daten und hängt, wenn dort Text steht und ein Objekt zurückkommt.
		 */
		parseNew: function (column, text) {
			const value = this.parse(column, text);
			return value !== null && /^Edm\.Geo/.test(column.type) ? geoJson(value) : value;
		},

		text: function (value) {
			if (value === null || value === undefined) {
				return "";
			}
			return typeof value === "object" ? wkt(value) : String(value);
		}
	};
});
