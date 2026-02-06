import dataPreferences from '@ohos.data.preferences'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'


const TAG = "PreferencesUtil"
const P_NAME = 'application_settings'
type ValueType = number | string | boolean | Array<number> | Array<string> | Array<boolean> | Uint8Array | object
  | bigint ;

export class PreferencesUtil {
  private static preferences: dataPreferences.Preferences
  private static preferencesAsync: Promise<dataPreferences.Preferences>

  private constructor() {
  }

  public static isInitialized() {
    if (PreferencesUtil.preferences) {
      return true;
    }
    return false;
  }

  public static async init(context: common.UIAbilityContext, name: string = P_NAME) {
    if (PreferencesUtil.preferences) return
    PreferencesUtil.preferences = dataPreferences.getPreferencesSync(context, { name })
    PreferencesUtil.preferencesAsync = dataPreferences.getPreferences(context, name).then(r => {
      return r
    })
  }

  private static async getPreferencesAsync(): Promise<dataPreferences.Preferences> {
    if (!(await PreferencesUtil.preferencesAsync)) {
      throw new Error('调用init()方法完成初始化')
    }
    return PreferencesUtil.preferencesAsync
  }


  private static getPreferences(): dataPreferences.Preferences {
    if (!PreferencesUtil.preferences) {
      throw new Error('调用init()方法完成初始化')
    }
    return PreferencesUtil.preferences
  }


  static async getAsync<T extends ValueType>(key: string, def?: ValueType): Promise<T> {
    const p = await PreferencesUtil.getPreferencesAsync()
    return new Promise<T>((resolve, reject) => {
      p.get(key, def, (err: BusinessError, data: dataPreferences.ValueType) => {
        if (err) {
          console.error(TAG, err.message)
          reject(def)
        }
        if (data) {
          resolve(data as T)
        }
      })
    })
  }


  static get<T extends ValueType>(key: string, def?: ValueType): T {
    try {
      return PreferencesUtil.getPreferences().getSync(key, def) as T
    } catch (e) {
      console.error(TAG, e)
    }
    return def as T
  }


  static async getAllAsync(): Promise<Object> {
    let preferences = await PreferencesUtil.getPreferencesAsync()
    return preferences.getAll()
  }

  static getAll(): Object | null {
    try {
      return PreferencesUtil.getPreferences().getAllSync()
    } catch (e) {
      console.error(TAG, e)
    }
    return null
  }

  static async putAsync(key: string, value: ValueType): Promise<void> {
    const r = await PreferencesUtil.getPreferencesAsync().then(async (p) => {
      await p.put(key, value)
      await p.flush();
    }).catch((err: Error) => {
      console.error(TAG, err.message)
    })
    return r
  }


  static put(key: string, value: ValueType): void {
    try {
      PreferencesUtil.getPreferences().putSync(key, value)
      PreferencesUtil.getPreferences().flush()
    } catch (e) {
      console.error(TAG, e)
    }

  }

  static hasKey(key: string): boolean {
    let has: boolean = false
    try {
      has = PreferencesUtil.getPreferences().hasSync(key)
    } catch (e) {
      console.error(TAG, e)
    }
    return has
  }

  static async deleteAsync(key: string): Promise<void> {
    return (await PreferencesUtil.getPreferencesAsync()).delete(key)
      .catch((err: Error) => {
        console.error(TAG, err.message)
      })
      .finally(async () => {
        (await PreferencesUtil.getPreferencesAsync()).flush()
      })
  }

  static delete(key: string): void {
    try {
      PreferencesUtil.getPreferences().deleteSync(key)
      PreferencesUtil.getPreferences().flush()
    } catch (e) {
      console.error(TAG, e)
    }
  }

  static async clearAsync(): Promise<void> {
    return (await PreferencesUtil.getPreferencesAsync()).clear()
      .catch((err: Error) => {
        console.error(TAG, err.message)
      })
      .finally(async () => {
        (await PreferencesUtil.getPreferencesAsync()).flush()
      })
  }

  static clear(): void {
    try {
      PreferencesUtil.preferences.clearSync()
      PreferencesUtil.preferences.flush()
    } catch (e) {
      console.error(TAG, e)
    }
  }
}
