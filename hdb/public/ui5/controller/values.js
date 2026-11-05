sap.ui.define([], function () {
	"use strict";

	/**
	 * Formulartext in den Modellwert: Edm.Int64 bleibt Text, weil JavaScript große Werte nicht exakt darstellt;
	 * Edm.Double wird eine Zahl. Leere Felder sind NULL. Wirft mit dem i18n-Schlüssel, wenn die Eingabe nicht passt.
	 */
	return {
		parse: function (column, text) {
			const value = text.trim();
			if (column.type === "Edm.String") {
				return text === "" ? null : text;
			}
			if (value === "") {
				return null;
			}
			if (column.type === "Edm.Int64") {
				if (!/^-?\d+$/.test(value)) {
					throw new Error("invalidInteger");
				}
				return value;
			}
			const number = Number(value);
			if (!Number.isFinite(number)) {
				throw new Error("invalidNumber");
			}
			return number;
		},

		text: function (value) {
			return value === null || value === undefined ? "" : String(value);
		}
	};
});
