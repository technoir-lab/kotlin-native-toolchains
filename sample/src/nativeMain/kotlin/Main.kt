import kotlinx.cinterop.ExperimentalForeignApi
import sample.greeting.greet

@OptIn(ExperimentalForeignApi::class)
fun main() {
    greet()
}
