import React from 'react';
import { Routes, Route } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import LoginPage from './pages/LoginPage';
import SignUpPage from './pages/SignUpPage';
import DashboardPage from './pages/DashboardPage';
import StudentsPage from './pages/StudentsPage';
import RoomsPage from './pages/RoomsPage';
import FeesPage from './pages/FeesPage';
import VisitorsPage from './pages/VisitorsPage';
import MaintenancePage from './pages/MaintenancePage';
import ReportsPage from './pages/ReportsPage';
import ProtectedRoute from './components/ProtectedRoute';
import MainLayout from './components/layout/MainLayout';
import StudentDetailPage from './pages/details/StudentDetailPage';
import RoomDetailPage from './pages/details/RoomDetailPage';
import FeeDetailPage from './pages/details/FeeDetailPage';
import VisitorDetailPage from './pages/details/VisitorDetailPage';
import MaintenanceDetailPage from './pages/details/MaintenanceDetailPage';

function App() {
    return (
        <AuthProvider>
            <Routes>
                <Route path="/login" element={<LoginPage />} />
                <Route path="/signup" element={<SignUpPage />} />
                <Route path="/" element={<ProtectedRoute />}>
                    <Route element={<MainLayout />}>
                        <Route path="/" element={<DashboardPage />} />
                        <Route path="/students" element={<StudentsPage />} />
                        <Route path="/students/:id" element={<StudentDetailPage />} />
                        <Route path="/rooms" element={<RoomsPage />} />
                        <Route path="/rooms/:id" element={<RoomDetailPage />} />
                        <Route path="/fees" element={<FeesPage />} />
                        <Route path="/fees/:id" element={<FeeDetailPage />} />
                        <Route path="/visitors" element={<VisitorsPage />} />
                        <Route path="/visitors/:id" element={<VisitorDetailPage />} />
                        <Route path="/maintenance" element={<MaintenancePage />} />
                        <Route path="/maintenance/:id" element={<MaintenanceDetailPage />} />
                        <Route path="/reports" element={<ReportsPage />} />
                    </Route>
                </Route>
            </Routes>
        </AuthProvider>
    );
}

export default App;
