# Рекомендации по архитектуре приложения

Этот документ содержит общие архитектурные принципы и рекомендации для Android-приложений.

```xml
<architecture>
    <item>Decompose компоненты используются для абстракции презентационного слоя от UI</item>
    <item>`io.podlodka.ai.core.decompose.RenderableComponent` – это интерфейс для компонентов с UI</item>
    <item>Компоненты будут создаваться с помощью конструкторов, без DI фреймворков и фабрик</item>
</architecture>
```

## Пример компонента

```kotlin
import androidx.compose.ui.Modifier
import from kotlinx.coroutines.flow.StateFlow
// Остальные импорты

interface SplashComponent : RenderableComponent {

    val state: StateFlow<State>

    data class State(
        val localization: Localization,
        val isLoading: Boolean = true,
    ) {
        // Части стейта должны быть организованы как его подклассы
        // Все строки, необходимые для UI должны быть заданы здесь
        data class Localization(
            val title: String,
        )
    }
}

class DefaultSplashComponent(
    componentContext: ComponentContext,
) : SplashComponent,
    ComponentContext by componentContext {
        
    private val _state = MutableStateFlow(
        InternalSplashComponent.State(
            localization = InternalSplashComponent.State.Localization(
                title = "Заголовок",
            ),
        )
    )
    override val state = _state.asStateFlow()

    @Composable
    override fun Render(modifier: Modifier) {
        SplashContent(
            component = this,
            modifier = modifier,
        )
    }
}
```

UI рекомендуется создавать с суффиксом `Content`.

```kotlin
@Composable
fun SplashContent(
    component: SplashComponent, // Composable функция принимает интерфейс компонента, получает стейт и сообщает о событях через него
    modifier: Modifier = Modifier,
) {
    val state by component.state.collectAsStateWithLifecycle() // А не collectAsState()
    Box(modifier = modifier) {
        if (state.isLoading) {
            CircularProgressIndicator()
        }
    }
}

@PreviewLightDark
@Composable
private fun SplashContentPreview() {
    CustomTheme {
        val component by remember { PreviewSplashComponent() }
        component.Render(modifier = Modifier.fillMaxSize())
    }
}

// Специальный компонент с моковым поведением для Preview
private class PreviewSplashComponent : InternalSplashComponent {
    override val state = MutableStateFlow(State())

    @Composable
    override fun Render(modifier: Modifier) {
        SplashContent(component = this, modifier = modifier)
    }
}
```
