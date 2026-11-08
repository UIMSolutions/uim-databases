sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/m/ActionSheet",
	"sap/m/Button",
	"sap/m/Dialog",
	"sap/m/Input",
	"sap/m/Label",
	"sap/m/MessageStrip",
	"sap/m/MessageToast",
	"sap/ui/layout/form/SimpleForm"
], function (Controller, ActionSheet, Button, Dialog, Input, Label, MessageStrip, MessageToast, SimpleForm) {
	"use strict";

	/** Wie AccessService.minPasswordLength: der Server prüft es ohnehin, so kommt die Meldung früher und übersetzt. */
	const MIN_PASSWORD_LENGTH = 12;

	return Controller.extend("hdb.client.controller.App", {
		onInit: function () {
			const component = this.getOwnerComponent();
			this.getView().addStyleClass(component.getContentDensityClass ? component.getContentDensityClass() : "sapUiSizeCompact");
			Promise.all(["login", "tables", "rows", "row", "backups", "statistics", "help"].map(function (id) {
				return this.byId(id).loaded();
			}, this)).then(component.viewsLoaded);
			const router = component.getRouter();
			const app = component.getModel("app");
			router.getRoute("home").attachPatternMatched(function () {
				app.setProperty("/layout", "OneColumn");
			});
			router.attachRouteMatched(function (event) {
				const route = event.getParameter("name");
				app.setProperty("/navKey", route === "table" || route === "row" ? "home" : route);
			});
			const showMid = function (id, layout) {
				this.byId("fcl").toMidColumnPage(this.byId(id).getId());
				app.setProperty("/layout", layout);
			}.bind(this);
			router.getRoute("table").attachPatternMatched(showMid.bind(null, "rows", "TwoColumnsMidExpanded"));
			router.getRoute("row").attachPatternMatched(showMid.bind(null, "rows", "ThreeColumnsMidExpanded"));
			router.getRoute("backups").attachPatternMatched(showMid.bind(null, "backups", "MidColumnFullScreen"));
			router.getRoute("statistics").attachPatternMatched(showMid.bind(null, "statistics", "MidColumnFullScreen"));
			router.getRoute("help").attachPatternMatched(showMid.bind(null, "help", "MidColumnFullScreen"));
		},

		initials: function (name) {
			return (name || "?").slice(0, 2).toUpperCase();
		},

		onToggleSideNav: function () {
			this.byId("toolPage").toggleSideContentMode();
		},

		/** Die Schlüssel der Navigationseinträge sind Routennamen. */
		onSideNavSelect: function (event) {
			this.getOwnerComponent().getRouter().navTo(event.getParameter("item").getKey());
		},

		onProfile: function (event) {
			const component = this.getOwnerComponent();
			const bundle = component.getModel("i18n").getResourceBundle();
			const app = component.getModel("app");
			const avatar = event.getParameter("avatar");
			const current = component.getLanguages().find(function (language) {
				return language.key === component.getLanguage();
			});
			this._openSheet(bundle.getText("profileTitle", [app.getProperty("/user"), app.getProperty("/role"), app.getProperty("/userTenant")]), avatar, [
				new Button({ text: bundle.getText("backups"), icon: "sap-icon://product", visible: app.getProperty("/isAdmin"), press: function () {
					component.getRouter().navTo("backups");
				} }),
				new Button({ text: bundle.getText("adminConsole"), icon: "sap-icon://action-settings", press: function () {
					window.location.href = "/admin";
				} }),
				new Button({ text: bundle.getText("changePassword"), icon: "sap-icon://key", press: function () {
					this._menu.attachEventOnce("afterClose", this._openPasswordDialog.bind(this));
				}.bind(this) }),
				new Button({ text: bundle.getText("languageCurrent", [current.name]), icon: "sap-icon://world", press: function () {
					// Ein zweites Blatt öffnet sich erst, wenn das erste zu ist
					this._menu.attachEventOnce("afterClose", this._openLanguages.bind(this, avatar));
				}.bind(this) }),
				new Button({ text: bundle.getText("signOut"), icon: "sap-icon://log", press: function () {
					component.endSession();
				} })
			]);
		},

		_openLanguages: function (avatar) {
			const component = this.getOwnerComponent();
			const current = component.getLanguage();
			this._openSheet(component.getModel("i18n").getResourceBundle().getText("language"), avatar, component.getLanguages().map(function (language) {
				return new Button({
					text: language.name,
					icon: language.key === current ? "sap-icon://accept" : "",
					press: function () {
						if (language.key !== current) {
							component.setLanguage(language.key);
						}
					}
				});
			}));
		},

		/**
		 * Der Server beendet nach dem Wechsel alle Sitzungen des Benutzers, auch diese. Deshalb gleich mit dem neuen
		 * Passwort neu anmelden; scheitert das, bleibt die Anmeldeseite mit einem Hinweis.
		 */
		_openPasswordDialog: function () {
			const component = this.getOwnerComponent();
			const bundle = component.getModel("i18n").getResourceBundle();
			const text = bundle.getText.bind(bundle);
			const user = component.getModel("app").getProperty("/user");
			const tenant = component.getModel("app").getProperty("/userTenant");
			const field = function (autocomplete) {
				const input = new Input({ type: "Password", width: "100%" });
				input.addEventDelegate({
					onAfterRendering: function () {
						input.getFocusDomRef().setAttribute("autocomplete", autocomplete);
					}
				});
				return input;
			};
			const current = field("current-password");
			const replacement = field("new-password");
			const confirm = field("new-password");
			const error = new MessageStrip({ type: "Error", showIcon: true, visible: false }).addStyleClass("sapUiSmallMargin");
			const showError = function (message) {
				error.setText(message);
				error.setVisible(true);
			};
			const submit = function () {
				error.setVisible(false);
				if (!current.getValue()) {
					showError(text("passwordCurrentMissing"));
					return;
				}
				if (replacement.getValue().length < MIN_PASSWORD_LENGTH) {
					showError(text("passwordTooShort", [MIN_PASSWORD_LENGTH]));
					return;
				}
				if (replacement.getValue() !== confirm.getValue()) {
					showError(text("passwordMismatch"));
					return;
				}
				const newPassword = replacement.getValue();
				dialog.setBusy(true);
				component.authFetch("/api/v1/auth/password", {
					method: "POST",
					headers: { "Content-Type": "application/json" },
					body: JSON.stringify({ current: current.getValue(), replacement: newPassword })
				}).then(function () {
					dialog.close();
					component.endSession("", true);
					return component.login(user, newPassword, tenant).then(function () {
						MessageToast.show(text("passwordChanged"));
					}, function () {
						component.getModel("app").setProperty("/loginError", text("passwordChangedSignIn"));
					});
				}, function (failure) {
					dialog.setBusy(false);
					if (component.handleError(failure)) {
						dialog.close();
						return;
					}
					showError(failure.message);
				});
			};
			[current, replacement, confirm].forEach(function (input) {
				input.attachSubmit(submit);
			});
			const dialog = new Dialog({
				title: text("changePassword"),
				contentWidth: "26rem",
				initialFocus: current,
				content: [
					error,
					new SimpleForm({ editable: true, layout: "ColumnLayout", content: [
						new Label({ text: text("passwordCurrent"), labelFor: current, required: true }), current,
						new Label({ text: text("passwordNew"), labelFor: replacement, required: true }), replacement,
						new Label({ text: text("passwordConfirm"), labelFor: confirm, required: true }), confirm
					] })
				],
				beginButton: new Button({ text: text("save"), type: "Emphasized", press: submit }),
				endButton: new Button({ text: text("cancel"), press: function () {
					dialog.close();
				} }),
				afterClose: function () {
					dialog.destroy();
				}
			});
			this.getView().addDependent(dialog);
			dialog.open();
		},

		_openSheet: function (title, opener, buttons) {
			if (this._menu) {
				this._menu.destroy();
			}
			this._menu = new ActionSheet({ title: title, placement: "Bottom", buttons: buttons });
			this.getView().addDependent(this._menu);
			this._menu.openBy(opener);
		}
	});
});
