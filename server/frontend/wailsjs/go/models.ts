export namespace main {
	
	export class LaunchFlags {
	    Minimized: boolean;
	    AutoStartMode: string;
	
	    static createFrom(source: any = {}) {
	        return new LaunchFlags(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.Minimized = source["Minimized"];
	        this.AutoStartMode = source["AutoStartMode"];
	    }
	}
	export class LogEntry {
	    level: string;
	    message: string;
	    timestamp: number;
	
	    static createFrom(source: any = {}) {
	        return new LogEntry(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.level = source["level"];
	        this.message = source["message"];
	        this.timestamp = source["timestamp"];
	    }
	}

}

