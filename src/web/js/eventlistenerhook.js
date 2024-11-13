"use strict";

// https://gist.github.com/fuzmish/bd444b1aadc2d22aada7c9b1a6de56ba

const EventListenerHook = {
	EventListeners: {},
	RawAddEventListener: EventTarget.prototype.addEventListener,
	FakeAddEventListener(eventTarget, ...args) {
		const eventName = args[0]

		if (!(eventTarget in this.EventListeners)) {
			this.EventListeners[eventTarget] = {}
		}

		if (!(eventName in this.EventListeners[eventTarget])) {
			this.EventListeners[eventTarget][eventName] = []
		}

		this.EventListeners[eventTarget][eventName].push(args.slice(1))

		return this.RawAddEventListener.apply(eventTarget, args)
	},
	InjectAddEventListenerHook() {
		EventTarget.prototype.addEventListener = function (...args) {
			return EventListenerHook.FakeAddEventListener(this, ...args)
		}
	}
}

EventListenerHook.InjectAddEventListenerHook()
