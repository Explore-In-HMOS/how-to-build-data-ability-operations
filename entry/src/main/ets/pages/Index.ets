import { SyncStatusMatrix } from './SyncStatusMatrix';
import { ScreenMetrics } from '../common/ScreenMetrics';

@Entry
@Component
struct Index {
  private pageStack: NavPathStack = new NavPathStack();
  @State private contentWidth: number = 172;

  aboutToAppear(): void {
    this.contentWidth = ScreenMetrics.safeContentWidthVp();
  }

  @Builder
  pageMap(name: string) {
    if (name === 'syncStatus') {
      SyncStatusMatrix()
    }
  }

  build() {
    Navigation(this.pageStack) {
      Stack() {
        Column({ space: 12 }) {
          Text('⌚')
            .fontSize(30)

          Text('Health Sync')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)

          Text('Watch ⇄ Phone batch sync')
            .fontSize(11)
            .fontColor('#9A9A9A')
            .maxLines(2)
            .textAlign(TextAlign.Center)

          Button('Open Sync Status')
            .width('100%')
            .height(40)
            .fontSize(14)
            .margin({ top: 4 })
            .onClick(() => {
              this.pageStack.pushPath({ name: 'syncStatus' });
            })
        }
        .width(this.contentWidth)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Center)
      .backgroundColor(Color.Black)
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
  }
}
