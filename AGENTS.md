# 项目目标

Yomink 是一款 iOS 原生 TXT 阅读器，目标是打造轻量、流畅、省电、纯本地的阅读体验。

- 必须兼容 iOS 15.5+。
- 必须以 UIKit 原生界面为核心。
- 必须坚持阅读引擎优先、UI 次之、性能第一。
- 必须纯本地运行，无网络依赖、无广告、无统计 SDK、无数据收集。
- 必须优先保证 100MB 级 TXT 文件的秒开、低内存、低 CPU 和低发热。

# 技术栈

项目默认技术栈如下，后续实现必须优先沿用：

- UIKit：主 UI 框架。
- UICollectionView：阅读分页、横向翻页、纵向滚动和页面复用的核心容器。
- CoreText：TXT 正文分页和排版的核心引擎。
- TextKit2：仅作为辅助能力，用于编辑、搜索高亮等非核心阅读场景。
- mmap：大 TXT 文件读取的基础能力。
- GRDB.swift：SQLite 数据库访问层。
- SQLite FTS5：全文搜索索引。
- Combine：轻量状态流和模块间事件传递。
- NSCache：页面、排版和临时文本窗口缓存。

# 架构规范

- 阅读引擎必须独立于 UI 层，UI 只能调用阅读引擎暴露的稳定接口。
- 阅读引擎必须围绕 byte offset、mmap、文本窗口、CoreText 分页和页面缓存设计。
- 数据层必须通过 Repository 或明确的数据服务暴露，不允许 Feature 层散落 SQL。
- 分页、章节解析、全文搜索、内容过滤、进度定位必须拆成独立模块。
- 书籍阅读进度必须以 byte offset 为权威坐标，页码、百分比和章节位置只能作为派生状态。
- 章节解析、全文索引、缓存构建必须渐进、可取消、可暂停，不得阻塞首屏阅读。
- 排版配置变化时，必须有明确的分页缓存失效策略，不能复用错误布局结果。
- 阅读静止状态下不得存在持续后台计算、轮询、无意义计时器或高频状态刷新。

# UI规范

- 所有核心界面必须使用 UIKit 实现。
- 阅读核心禁止使用 SwiftUI、WebView 或 UIPageViewController。
- 阅读页必须以 UICollectionView 为核心，依靠 cell 复用、预取和局部更新保持稳定帧率。
- 菜单、抽屉、弹窗、底部面板不得影响阅读静止状态 CPU。
- 阅读界面优先保证稳定、流畅、低功耗，再考虑复杂视觉效果。
- 翻页、滚动、进度拖动等高频交互必须避免触发全量刷新。
- 列表或阅读页更新时必须优先使用局部更新、diff 或定向 cell 更新。
- 禁止为了简单实现而频繁调用 reloadData，尤其是阅读页 UICollectionView。
- UI 更新必须回到主线程；分页、搜索、解析、文件读取不得在主线程执行。

# 性能规范

- 100MB TXT < 0.5秒打开，并渲染出第一页可读文字。
- 阅读内存 < 50MB。
- 静止 CPU 接近 0%。
- 不允许一次性读取全文。
- 不允许把整本书转换为 String。
- 不允许为整本书构建大型 NSAttributedString。
- 不允许在主线程执行分页、全文搜索、章节解析、编码转换或大文件扫描。
- 不允许在翻页过程中创建大量临时对象或长期持有大文本对象。
- 页面缓存必须有上限，优先缓存当前页、前后页和少量邻近页面。
- 后台任务必须限速，并在用户开始阅读、翻页或退出页面时及时让出资源。

# 文件组织规范

推荐文件组织如下，后续新增文件必须尽量按职责放置：

```text
Yomink/
  App/
  Core/
    ReaderEngine/
      FileMapping/
      Encoding/
      TextWindow/
      Pagination/
      ChapterParsing/
      PageCache/
      ProgressLocator/
    Database/
      Migrations/
      Models/
      Repositories/
    Search/
    Settings/
  Features/
    Bookshelf/
    Import/
    Reader/
    ReaderMenu/
    CatalogAndBookmarks/
    BookSearch/
    ContentFilter/
    Groups/
    AppSettings/
  UI/
    Components/
    Panels/
    Drawers/
    Themes/
  Resources/
  Tests/
```

- `Core/ReaderEngine/` 只放阅读引擎核心，不依赖具体页面控制器。
- `Core/Database/` 只放数据库连接、迁移、模型和 Repository。
- `Features/` 按业务功能拆分，每个功能维护自己的 ViewController、ViewModel 和协调逻辑。
- `UI/` 只放可复用 UIKit 组件，不包含业务规则。
- `Tests/` 必须覆盖阅读引擎、分页、进度恢复、数据库和性能关键路径。

# Swift代码规范

- 使用 Swift 编写，优先保持类型小、方法短、职责清晰。
- 大文件处理、分页、搜索、章节解析必须使用后台队列、async 任务或受控调度。
- UI 相关代码必须只在主线程更新界面。
- 对性能敏感路径必须避免隐式大拷贝、过度桥接和无界数组增长。
- 数据模型应优先使用值类型；涉及 mmap 生命周期、缓存和数据库连接时可使用引用类型。
- 协议只在能稳定边界、便于测试或隔离模块时引入，不为抽象而抽象。
- 错误处理必须明确，不允许吞掉文件读取、编码识别、数据库迁移等关键错误。
- 缓存必须可清理、可限制大小，并能响应内存警告。

# 命名规范

- 类型名必须表达领域含义，避免泛泛的 Manager、Helper、Util。
- 推荐命名示例：
  - `BookFileMapping`
  - `TextWindow`
  - `TextDecoder`
  - `CoreTextPaginator`
  - `PageByteRange`
  - `ReaderPageCache`
  - `ReadingProgressStore`
  - `ChapterParser`
  - `SearchIndexService`
  - `BookRepository`
- 与 byte offset 相关的属性必须在名称中体现 `byteOffset` 或 `byteRange`。
- 与字符索引、页码、章节序号相关的字段不得混用命名。
- ViewController、ViewModel、Repository、Service、Cache、Store 等后缀必须按真实职责使用。

# 注释规范

- 注释必须解释原因、约束或性能风险，不重复代码表面含义。
- 必须为以下复杂逻辑添加简短注释：
  - mmap 生命周期管理。
  - byte offset 与解码文本窗口的映射。
  - CoreText 分页边界计算。
  - 分页缓存失效策略。
  - 章节解析和全文索引的分块策略。
  - 避免主线程卡顿或避免大内存分配的关键代码。
- 不允许写空泛注释，例如“初始化变量”“设置属性”“执行操作”。
- 任何临时性能折中必须在注释中说明原因和后续处理条件。

# 禁止事项

以下事项在本项目中默认禁止，除非用户明确修改项目目标：

- 禁止使用 WebView 实现阅读核心。
- 禁止使用 SwiftUI 作为核心 UI 或阅读界面主体。
- 禁止 UIPageViewController。
- 禁止使用 UIPageViewController 实现阅读核心。
- 禁止一次性读取全文。
- 禁止把整本 TXT 转成完整 String。
- 禁止大型 NSAttributedString。
- 禁止构建大型 NSAttributedString。
- 禁止主线程分页。
- 禁止主线程大文件解析。
- 禁止主线程全文搜索。
- 禁止全文 regex 扫描大文件。
- 禁止频繁 reloadData，尤其是阅读页 UICollectionView。
- 禁止无上限页面缓存、无上限文本缓存和无上限搜索结果缓存。
- 禁止在阅读静止状态运行轮询、计时器、自动预分页风暴或持续后台任务。
- 禁止接入广告 SDK。
- 禁止接入统计 SDK。
- 禁止发起网络请求。
- 禁止添加非必要网络权限。
- 禁止为 UI 便利牺牲阅读首屏速度、内存和 CPU 目标。

# 阅读器特殊性能要求

- 阅读核心必须基于 mmap + CoreText + UICollectionView。
- 打开书籍时只能读取当前首屏所需的最小文本窗口。
- 100MB TXT < 0.5秒打开，必须优先显示第一页，而不是等待目录、索引或全书分页完成。
- 阅读内存 < 50MB，任何实现都不得长期持有整本书文本、全量页面文本或大型 NSAttributedString。
- 静止 CPU 接近 0%，阅读页面无操作时不得继续分页、扫描、索引或刷新 UI。
- byte offset 是唯一权威阅读进度；恢复阅读时必须从 byte offset 定位文本窗口并重新分页。
- CoreText 分页必须在后台完成，并只把轻量页面结果传回 UI。
- UICollectionView 必须稳定复用 cell，翻页时避免频繁 reloadData。
- 章节解析必须分块、渐进、可取消，禁止全文 regex。
- 全文搜索必须基于 SQLite FTS5 或分块索引，禁止临时全书扫描。
- 内容过滤必须在当前文本窗口或页面范围内应用，禁止生成整本书替换副本。
- 自动阅读必须使用低频、可控、可暂停的调度方式，退出后必须停止所有相关计时器或 display link。
- 收到内存警告时必须释放可重建缓存，保留必要进度和当前阅读状态。
