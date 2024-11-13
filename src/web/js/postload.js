"use strict";

addEventListener("load", () => {
	document.body.removeEventListener("contextmenu", EventListenerHook.EventListeners[document.body].contextmenu[0][0]);

	const tooltipTriggerList = document.querySelectorAll('[data-bs-toggle="tooltip"]')
	const tooltipList = [...tooltipTriggerList].map(tooltipTriggerEl => new bootstrap.Tooltip(tooltipTriggerEl))
});

document.addEventListener('DOMContentLoaded', () => {
	if (typeof webui == undefined) return;

	webui.setEventCallback((event) => {
		if (event != webui.event.CONNECTED) return;

		initializeUI();
	})
});
