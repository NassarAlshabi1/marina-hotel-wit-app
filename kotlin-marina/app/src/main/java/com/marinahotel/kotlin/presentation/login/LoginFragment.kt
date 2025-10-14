package com.marinahotel.kotlin.presentation.login

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.widget.doOnTextChanged
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.fragment.findNavController
import com.google.android.material.snackbar.Snackbar
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.FragmentLoginBinding
import com.marinahotel.kotlin.presentation.common.hotelRepository
import com.marinahotel.kotlin.presentation.HotelViewModelFactory
import kotlinx.coroutines.launch

class LoginFragment : Fragment() {

    private var _binding: FragmentLoginBinding? = null
    private val binding: FragmentLoginBinding get() = _binding!!

    private val viewModel: LoginViewModel by viewModels {
        HotelViewModelFactory { LoginViewModel(hotelRepository()) }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentLoginBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setupListeners()
        observeState()
        observeEvents()
    }

    private fun setupListeners() {
        binding.usernameInput.doOnTextChanged { text, _, _, _ ->
            viewModel.onUsernameChanged(text?.toString().orEmpty())
        }
        binding.passwordInput.doOnTextChanged { text, _, _, _ ->
            viewModel.onPasswordChanged(text?.toString().orEmpty())
        }
        binding.loginButton.setOnClickListener {
            viewModel.submit()
        }
    }

    private fun observeState() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    binding.loginButton.isEnabled = !state.isLoading
                    binding.usernameLayout.isEnabled = !state.isLoading
                    binding.passwordLayout.isEnabled = !state.isLoading

                    binding.usernameLayout.error = null
                    binding.passwordLayout.error = null
                    if (state.errorMessageRes != null) {
                        val message = getString(state.errorMessageRes)
                        binding.passwordLayout.error = message
                        Snackbar.make(binding.root, message, Snackbar.LENGTH_SHORT).show()
                    }
                }
            }
        }
    }

    private fun observeEvents() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.events.collect { event ->
                    when (event) {
                        LoginViewModel.LoginEvent.NavigateToDashboard -> {
                            findNavController().navigate(R.id.action_loginFragment_to_dashboardFragment)
                        }
                    }
                }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
