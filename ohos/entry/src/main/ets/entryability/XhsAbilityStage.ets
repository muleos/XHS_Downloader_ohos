import { AbilityStage } from '@kit.AbilityKit';
import { AppContainer } from '../data/AppContainer';

export default class XhsAbilityStage extends AbilityStage {
  onCreate(): void {
    AppContainer.get().init(this.context);
  }
}
