package com.example.studenthelper.ui.navigation

import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.studenthelper.ui.chinese.ChineseScreen
import com.example.studenthelper.ui.composition.CompositionDetailScreen
import com.example.studenthelper.ui.composition.CompositionListScreen
import com.example.studenthelper.ui.composition.CompositionNewScreen
import com.example.studenthelper.ui.english.EnglishScreen
import com.example.studenthelper.ui.favorites.FavoritesScreen
import com.example.studenthelper.ui.math.MathScreen
import com.example.studenthelper.ui.me.MeScreen
import com.example.studenthelper.ui.me.SettingsScreen

@Composable
fun StudentHelperRoot() {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val showBottomBar = currentRoute in BottomTab.entries.map { it.route }

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                AppBottomBar(
                    currentRoute = currentRoute,
                    onTabSelected = { tab ->
                        navController.navigate(tab.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                )
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = BottomTab.MATH.route,
            enterTransition = { fadeIn(tween(180)) },
            exitTransition = { fadeOut(tween(120)) },
            popEnterTransition = { fadeIn(tween(180)) },
            popExitTransition = { fadeOut(tween(120)) },
            modifier = Modifier.padding(innerPadding),
        ) {
            composable(
                BottomTab.CHINESE.route,
                arguments = listOf(navArgument("subject") { defaultValue = "chinese" }),
            ) { ChineseScreen() }
            composable(
                BottomTab.MATH.route,
                arguments = listOf(navArgument("subject") { defaultValue = "math" }),
            ) { MathScreen() }
            composable(
                BottomTab.ENGLISH.route,
                arguments = listOf(navArgument("subject") { defaultValue = "english" }),
            ) { EnglishScreen() }

            composable(BottomTab.COMPOSITION.route) {
                CompositionListScreen(
                    onNewComposition = { navController.navigate(Routes.COMPOSITION_NEW) },
                    onOpenDetail = { id -> navController.navigate(Routes.compositionDetail(id)) },
                )
            }
            composable(Routes.COMPOSITION_NEW) {
                CompositionNewScreen(
                    onBack = { navController.popBackStack() },
                    onSubmitted = { id ->
                        navController.navigate(Routes.compositionDetail(id)) {
                            popUpTo(BottomTab.COMPOSITION.route)
                        }
                    },
                )
            }
            composable(
                "${Routes.COMPOSITION_DETAIL}/{id}",
                arguments = listOf(navArgument("id") { type = NavType.LongType }),
            ) {
                CompositionDetailScreen(onBack = { navController.popBackStack() })
            }

            composable(BottomTab.ME.route) {
                MeScreen(
                    onOpenFavorites = { navController.navigate(Routes.FAVORITES) },
                    onOpenSettings = { navController.navigate(Routes.SETTINGS) },
                )
            }
            composable(Routes.FAVORITES) { FavoritesScreen(onBack = { navController.popBackStack() }) }
            composable(Routes.SETTINGS) { SettingsScreen(onBack = { navController.popBackStack() }) }
        }
    }
}
